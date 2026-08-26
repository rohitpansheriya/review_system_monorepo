/**
 * razorpay.ts
 *
 * Cloud Functions for payment, subscription and renewal lifecycle.
 *
 * ─── Callable Functions (require Firebase Auth) ────────────────────────────
 *   createOrder        — Creates a Razorpay order for the ₹1999 one-time
 *                        setup fee at enrollment time.
 *   createSubscription — Creates a Razorpay subscription against the existing
 *                        ₹999/year Plan for recurring annual renewal.
 *   resendPaymentLink  — Creates a fresh Razorpay Payment Link (short_url) for
 *                        a pending_payment draft, emails it to the owner via
 *                        the notifications service, and returns the short_url
 *                        so the employee can share it via WhatsApp/copy.
 *                        (Change 3)
 *
 * ─── HTTP Function ────────────────────────────────────────────────
 *   razorpayWebhook    — Receives Razorpay webhook events. Verifies
 *                        HMAC-SHA256 signature before processing. On success:
 *                          • Activates pending_payment draft: flips status →
 *                            "active", sets renewal_date = now + 1 year.
 *                          • Increments employee counters (activation-time only).
 *                          • Generates branded QR PNG for every branch (doc 09).
 *                          • Creates commission_records (online / verified).
 *
 * ─── Scheduled Functions (daily) ───────────────────────────────────
 *   renewalLifecycle       — Enforces subscription state machine:
 *                              active → grace_period (renewal_date passed)
 *                              grace_period → deleted (grace_period_ends passed)
 *                            NEVER reads pending_payment docs (query-level filter).
 *                            NEVER deletes commission_records (financial audit).
 *   cleanupAbandonedDrafts — Deletes pending_payment businesses older than
 *                            ABANDONED_DRAFT_AGE_HOURS (48h default) + their
 *                            branches. Keeps the DB clean.
 *
 * Secrets: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET
 * Params:  RAZORPAY_PLAN_ID  (set via: firebase functions:params:set
 *          RAZORPAY_PLAN_ID=...)
 *
 * See: docs/05-payment-subscription-renewal.md
 *      docs/06-commission-tracking.md
 */

import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  getFirestore,
  Timestamp,
  FieldValue,
  DocumentReference,
  Firestore,
} from "firebase-admin/firestore";
import * as crypto from "crypto";
import Razorpay from "razorpay";

import {
  razorpayKeyId,
  razorpayKeySecret,
  razorpayWebhookSecret,
  razorpayPlanId,
} from "./secrets.js";
import {buildQrForBranch, buildPlainQrForBranch} from "./qrGenerator.js";
import {sendPaymentLinkEmail} from "./notifications.js";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Setup fee in paise (₹1999 × 100). */
const SETUP_FEE_PAISE = 199900;

/** Annual renewal fee in paise (₹999 × 100) — for commission records. */
const RENEWAL_FEE_PAISE = 99900;

/** Grace period duration in days after renewal_date passes without payment. */
const GRACE_PERIOD_DAYS = 30;

/**
 * Age threshold in hours after which an unpaid draft (pending_payment) is
 * considered abandoned and eligible for cleanup.
 * Change this constant only — never scatter the value throughout the code.
 */
const ABANDONED_DRAFT_AGE_HOURS = 48;

/** Default standee status written to every branch on first activation. (Change 2) */
const STANDEE_STATUS_DEFAULT = "not_ordered";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Throws HttpsError(unauthenticated) if the caller has no Firebase Auth uid.
 * @param {object | undefined} auth - The auth context from the onCall request.
 */
function requireAuth(auth: {uid: string} | undefined): void {
  if (!auth?.uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to call this function."
    );
  }
}

/**
 * Returns a new Date that is exactly `years` years after `from`.
 * @param {Date} from - The base date.
 * @param {number} years - Number of years to add.
 * @return {Date}
 */
function addYears(from: Date, years: number): Date {
  const d = new Date(from);
  d.setFullYear(d.getFullYear() + years);
  return d;
}

/**
 * Returns a new Date that is exactly `days` days after `from`.
 * @param {Date} from - The base date.
 * @param {number} days - Number of days to add.
 * @return {Date}
 */
function addDays(from: Date, days: number): Date {
  return new Date(from.getTime() + days * 24 * 60 * 60 * 1000);
}

/**
 * Constant-time comparison of two strings to prevent timing attacks.
 * @param {string} a - First string.
 * @param {string} b - Second string.
 * @return {boolean}
 */
function safeEqual(a: string, b: string): boolean {
  try {
    return crypto.timingSafeEqual(
      Buffer.from(a, "utf8"),
      Buffer.from(b, "utf8")
    );
  } catch {
    // Buffer lengths differ — not equal.
    // timingSafeEqual throws when lengths differ.
    return false;
  }
}

/**
 * Provisions a Firebase Auth user account for the business owner, sets the
 * role = "owner" custom claim, updates businesses/{businessId}.owner_auth_uid,
 * and generates a magic password-reset / setup link.
 */
export async function provisionOwnerAccount(
  db: Firestore,
  businessId: string,
  ownerEmail: string,
  ownerName?: string
): Promise<string> {
  const auth = admin.auth();
  let uid: string;
  try {
    const existing = await auth.getUserByEmail(ownerEmail);
    uid = existing.uid;
  } catch {
    const newUser = await auth.createUser({
      email: ownerEmail,
      displayName: ownerName || "Business Owner",
    });
    uid = newUser.uid;
  }

  // Assign role: 'owner' custom claim
  await auth.setCustomUserClaims(uid, {role: "owner"});

  // Update business document with owner_auth_uid
  await db.collection("businesses").doc(businessId).update({
    owner_auth_uid: uid,
  });

  try {
    const link = await auth.generatePasswordResetLink(ownerEmail);
    logger.info("provisionOwnerAccount: magic setup link generated", {
      ownerEmail,
      businessId,
      link,
    });
  } catch (err) {
    logger.warn("provisionOwnerAccount: password reset link generation warning", {err});
  }

  return uid;
}

// ---------------------------------------------------------------------------
// createOrder  (callable)
// ---------------------------------------------------------------------------

/**
 * Creates a Razorpay order for the ₹1999 one-time setup fee.
 *
 * Input:  { businessId: string }
 * Output: { orderId: string, amount: number, currency: string, keyId: string }
 *
 * The keyId returned is the Razorpay Key ID — it is safe to expose to the
 * frontend (analogous to a Stripe publishable key). The Key Secret never
 * leaves the server.
 *
 * The caller must be authenticated (any role). The businessId is used as the
 * Razorpay order receipt so the webhook can map payment → business.
 */
export const createOrder = onCall(
  {
    secrets: [razorpayKeyId, razorpayKeySecret],
    maxInstances: 10,
    region: "asia-south1",
  },
  async (request) => {
    requireAuth(request.auth);

    const {businessId} = request.data as {businessId?: unknown};
    if (typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`businessId` must be a non-empty string."
      );
    }

    // Verify the business document actually exists.
    const db = admin.firestore();
    const bizSnap = await db.collection("businesses").doc(businessId).get();
    if (!bizSnap.exists) {
      throw new HttpsError("not-found", `Business '${businessId}' not found.`);
    }

    const branchesSnap = await db.collection("businesses").doc(businessId).collection("branches").get();
    const branchCount = Math.max(branchesSnap.size, 1);
    const totalAmountPaise = branchCount * SETUP_FEE_PAISE;

    const razorpay = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });

    let order: {id: string; amount: number; currency: string};
    try {
      order = await razorpay.orders.create({
        amount: totalAmountPaise,
        currency: "INR",
        // receipt is used by the webhook to map payment → business.
        receipt: businessId,
        notes: {
          businessId,
          type: "setup_fee",
          branchCount: String(branchCount),
        },
      }) as {id: string; amount: number; currency: string};
    } catch (err) {
      logger.error("Razorpay orders.create failed", {err, businessId});
      throw new HttpsError(
        "internal",
        "Failed to create payment order. Please try again."
      );
    }

    logger.info("createOrder: order created", {
      orderId: order.id,
      businessId,
      callerUid: request.auth?.uid,
    });

    return {
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      // keyId is the Razorpay Key ID — safe to return to frontend.
      keyId: razorpayKeyId.value(),
    };
  }
);

// ---------------------------------------------------------------------------
// createSubscription  (callable)
// ---------------------------------------------------------------------------

/**
 * Creates a Razorpay subscription against the existing ₹999/year Plan.
 *
 * Input:  { businessId: string }
 * Output: { subscriptionId: string, keyId: string }
 *
 * total_count is set to 0 (unlimited) — the subscription auto-renews each year
 * until explicitly cancelled. The subscriptionId is persisted on the business
 * doc so it can be cancelled later if needed.
 */
export const createSubscription = onCall(
  {
    secrets: [razorpayKeyId, razorpayKeySecret],
    maxInstances: 10,
    region: "asia-south1",
  },
  async (request) => {
    requireAuth(request.auth);

    const {businessId} = request.data as {businessId?: unknown};
    if (typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`businessId` must be a non-empty string."
      );
    }

    const db = admin.firestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const bizSnap = await bizRef.get();
    if (!bizSnap.exists) {
      throw new HttpsError("not-found", `Business '${businessId}' not found.`);
    }

    const planId = razorpayPlanId.value();
    if (!planId || planId.trim().length === 0) {
      logger.error("RAZORPAY_PLAN_ID param is not set");
      throw new HttpsError(
        "failed-precondition",
        "Subscription plan is not configured. Contact the administrator."
      );
    }

    const razorpay = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });

    let subscription: {id: string};
    try {
      subscription = await razorpay.subscriptions.create({
        plan_id: planId,
        // total_count: 0 is not a valid Razorpay param; use a very large number
        // for "indefinite" or omit. Razorpay requires total_count >= 1.
        // total_count: Razorpay caps this at 100 for the given period.
        // 100 years (for yearly plan) is effectively indefinite.
        total_count: 100,
        quantity: 1,
        notes: {
          businessId,
        },
      }) as {id: string};
    } catch (err) {
      logger.error(
        "Razorpay subscriptions.create failed",
        {err, businessId, planId}
      );
      throw new HttpsError(
        "internal",
        "Failed to create subscription. Please try again."
      );
    }

    // Persist the subscription ID on the business doc for future cancellation.
    await bizRef.update({
      razorpay_subscription_id: subscription.id,
    });

    logger.info("createSubscription: subscription created", {
      subscriptionId: subscription.id,
      businessId,
      planId,
      callerUid: request.auth?.uid,
    });

    return {
      subscriptionId: subscription.id,
      // keyId is safe to return to frontend (it is the public key).
      keyId: razorpayKeyId.value(),
    };
  }
);

// ---------------------------------------------------------------------------
// razorpayWebhook  (HTTP — no Auth, secured via HMAC-SHA256)
// ---------------------------------------------------------------------------

/**
 * Receives Razorpay webhook events.
 *
 * Security: every request must carry a valid X-Razorpay-Signature header.
 * The HMAC-SHA256 is computed over the raw request body using
 * RAZORPAY_WEBHOOK_SECRET. Requests with an invalid or missing signature are
 * rejected with HTTP 400 before any Firestore write takes place.
 *
 * Handled events:
 *   payment.captured      — one-time setup-fee order payment succeeded.
 *   subscription.charged  — annual subscription renewal payment succeeded.
 *
 * On a valid payment:
 *   1. Updates businesses/{id}:
 *        subscription_status  → "active"
 *        renewal_date         → now + 1 year
 *        grace_period_ends    → deleted (cleared)
 *   2. Creates a commission_records document:
 *        payment_mode: "online", status: "verified"
 *
 * All other events return HTTP 200 immediately (Razorpay retries on non-2xx).
 *
 * Webhook URL to configure in Razorpay dashboard → Settings → Webhooks:
 *   https://asia-south1-review-system-prod-49b7a.cloudfunctions.net/
 *   razorpayWebhook
 *   (Confirm the exact URL after first deploy.)
 */
export const razorpayWebhook = onRequest(
  {
    secrets: [razorpayKeyId, razorpayKeySecret, razorpayWebhookSecret],
    maxInstances: 10,
    region: "asia-south1",
    // rawBody must be available for HMAC verification.
    // onRequest preserves req.rawBody in Firebase Functions v2.
  },
  async (req, res) => {
    // ── 1. Only accept POST ───────────────────────────────────────────────
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    // ── 2. Verify HMAC-SHA256 signature ───────────────────────────────────
    const signature = req.headers["x-razorpay-signature"] as string | undefined;
    if (!signature) {
      logger.warn("razorpayWebhook: missing X-Razorpay-Signature header");
      res.status(400).json({error: "Missing signature"});
      return;
    }

    // req.rawBody is a Buffer in Firebase Functions v2 onRequest.
    const rawBody: Buffer = (req as unknown as {rawBody: Buffer}).rawBody;
    if (!rawBody) {
      logger.error("razorpayWebhook: rawBody is unavailable");
      res.status(400).json({error: "Cannot read request body"});
      return;
    }

    const expectedSig = crypto
      .createHmac("sha256", razorpayWebhookSecret.value())
      .update(rawBody)
      .digest("hex");

    if (!safeEqual(expectedSig, signature)) {
      logger.warn("razorpayWebhook: signature mismatch — rejecting");
      res.status(400).json({error: "Invalid signature"});
      return;
    }

    // ── 3. Parse event ────────────────────────────────────────────────────
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(rawBody.toString("utf8")) as Record<string, unknown>;
    } catch (err) {
      logger.error("razorpayWebhook: JSON parse error", {err});
      res.status(400).json({error: "Invalid JSON body"});
      return;
    }

    const eventName = event["event"] as string | undefined;
    logger.info("razorpayWebhook: received event", {eventName});

    // ── 4. Handle known events ────────────────────────────────────────────
    if (
      eventName === "payment.captured" ||
      eventName === "subscription.charged"
    ) {
      try {
        await handleSuccessfulPayment(eventName, event);
      } catch (err) {
        logger.error("razorpayWebhook: handleSuccessfulPayment threw", {
          eventName,
          err,
        });
        // Return 500 so Razorpay retries the webhook.
        res.status(500).json({error: "Internal processing error"});
        return;
      }
    } else {
      // Acknowledge receipt of events we don't handle.
      logger.info("razorpayWebhook: unhandled event (no-op)", {eventName});
    }

    // ── 5. Always return 200 for handled / acknowledged events ─────────────
    res.status(200).json({received: true});
  }
);

// ---------------------------------------------------------------------------
// handleSuccessfulPayment — shared logic for both payment events
// ---------------------------------------------------------------------------

/**
 * Processes a confirmed payment and ACTIVATES a pending_payment draft.
 *
 * This is the ONLY code path that may:
 *   • Flip subscription_status to "active".
 *   • Set renewal_date (THIS starts the renewal clock).
 *   • Increment employee counters.
 *
 * Actions:
 *   1. Flips subscription_status: pending_payment → "active".
 *      (Also handles re-payments on grace_period / expired active subs.)
 *   2. Sets renewal_date = now + 1 year (or extends existing future date).
 *   3. Clears grace_period_ends (if present).
 *   4. Increments enrolled_by employee's total_enrollments / this_month_enrollments.
 *      (Skipped for renewal payments where status was already "active" or
 *      "grace_period" — counters only increment once per enrollment.)
 *   5. STUB: triggers QR/NFC generation for each branch (doc 09).
 *   6. Creates a commission_records document
 *      (payment_mode: "online", status: "verified").
 *
 * @param {string} eventName - Razorpay event name.
 * @param {object} event - Full parsed webhook payload.
 */
async function handleSuccessfulPayment(
  eventName: string,
  event: Record<string, unknown>
): Promise<void> {
  const payload = event["payload"] as Record<string, unknown> | undefined;
  if (!payload) {
    logger.error("handleSuccessfulPayment: missing payload", {eventName});
    return;
  }

  let businessId: string | undefined;
  let branchId: string | undefined;
  let amountPaise: number;

  if (eventName === "payment.captured") {
    // payment.captured: businessId from order.receipt (set in createOrder)
    const paymentEntity = (
      (payload["payment"] as Record<string, unknown> | undefined)?.["entity"]
    ) as Record<string, unknown> | undefined;

    if (!paymentEntity) {
      logger.error("handleSuccessfulPayment: missing payment.entity");
      return;
    }

    // The order receipt is the businessId we set in createOrder.
    // Also check notes.businessId as a fallback.
    const notes =
      paymentEntity["notes"] as Record<string, unknown> | undefined;
    const descId =
      paymentEntity["description"] as string | undefined;
    const notesId = notes?.["businessId"] as string | undefined;
    businessId = descId ?? notesId;
    branchId = notes?.["branchId"] as string | undefined;

    // If still no businessId from notes, try fetching the order.
    if (!businessId) {
      const orderId = paymentEntity["order_id"] as string | undefined;
      if (!orderId) {
        logger.error(
          "handleSuccessfulPayment: cannot determine businessId",
          {paymentEntity}
        );
        return;
      }
      // Look up order receipt via Razorpay API.
      try {
        const razorpay = new Razorpay({
          key_id: razorpayKeyId.value(),
          key_secret: razorpayKeySecret.value(),
        });
        const orderData = await razorpay.orders.fetch(orderId) as {
          receipt?: string;
          notes?: Record<string, string>;
        };
        businessId =
          orderData.receipt ?? orderData.notes?.["businessId"];
        if (!branchId) {
          branchId = orderData.notes?.["branchId"];
        }
      } catch (err) {
        logger.error(
          "handleSuccessfulPayment: failed to fetch order",
          {orderId, err}
        );
        return;
      }
    }

    amountPaise =
      (paymentEntity["amount"] as number | undefined) ?? SETUP_FEE_PAISE;
  } else {
    // subscription.charged → businessId in subscription.notes.businessId
    const subscriptionEntity = (
      (payload["subscription"] as Record<string, unknown> | undefined)
        ?.["entity"]
    ) as Record<string, unknown> | undefined;

    const subNotes =
      subscriptionEntity?.["notes"] as Record<string, unknown> | undefined;
    businessId = subNotes?.["businessId"] as string | undefined;
    branchId = subNotes?.["branchId"] as string | undefined;
    amountPaise = RENEWAL_FEE_PAISE;
  }

  if (!businessId || businessId.trim().length === 0) {
    logger.error("handleSuccessfulPayment: could not determine businessId", {
      eventName,
      payload,
    });
    return;
  }

  const db = getFirestore();
  const bizRef = db.collection("businesses").doc(businessId);
  const bizSnap = await bizRef.get();

  if (!bizSnap.exists) {
    logger.error("handleSuccessfulPayment: business not found", {businessId});
    return;
  }

  const bizData = bizSnap.data() as {
    brand_name?: string;
    enrolled_by?: string;
    subscription_status?: string;
    renewal_date?: Timestamp;
    owner_email?: string;
    owner_name?: string;
    owner_auth_uid?: string | null;
  };

  const now = new Date();

  // RULE 4: THIS IS THE ONLY LINE IN THE SYSTEM THAT STARTS THE CLOCK.
  // For a pending_payment draft: renewal_date = now + 1 year.
  // For a renewal (active/grace_period): extend from existing future date.
  const isPendingDraft = bizData.subscription_status === "pending_payment";
  const baseDate =
    !isPendingDraft &&
    bizData.renewal_date &&
    bizData.renewal_date.toDate() > now ?
      bizData.renewal_date.toDate() :
      now;
  const newRenewalDate = addYears(baseDate, 1);

  // ── Firestore writes (all in one batch) ───────────────────────────────────
  const batch = db.batch();

  // 1. Activate business: flip status, start clock, clear grace, tag as online.
  batch.update(bizRef, {
    subscription_status: "active",
    renewal_date: Timestamp.fromDate(newRenewalDate),
    grace_period_ends: FieldValue.delete(),
    payment_mode: "online",
  });

  // 2. Increment employee counters — ONLY on first activation (draft → active).
  //    Renewal payments skip this to avoid double-counting.
  if (isPendingDraft && bizData.enrolled_by && bizData.enrolled_by !== "admin") {
    const empRef = db.collection("employees").doc(bizData.enrolled_by as string);
    const empSnap = await empRef.get();
    if (empSnap.exists) {
      batch.update(empRef, {
        total_enrollments: FieldValue.increment(1),
        this_month_enrollments: FieldValue.increment(1),
      });
      logger.info("handleSuccessfulPayment: employee counters incremented", {
        employeeId: bizData.enrolled_by,
        businessId,
      });
    }
  }

  await batch.commit();

  logger.info("handleSuccessfulPayment: business activated", {
    businessId,
    branchId,
    wasDraft: isPendingDraft,
    newRenewalDate: newRenewalDate.toISOString(),
    eventName,
    amountRupees: amountPaise / 100,
  });

  // Provision owner Auth user + assign role: 'owner' claim if email present
  if (bizData.owner_email && (!bizData.owner_auth_uid || isPendingDraft)) {
    try {
      const ownerUid = await provisionOwnerAccount(
        db,
        businessId,
        bizData.owner_email,
        bizData.owner_name
      );
      logger.info("handleSuccessfulPayment: owner account provisioned", {
        businessId, ownerUid,
      });
    } catch (ownerErr) {
      logger.error("handleSuccessfulPayment: owner provisioning failed", {
        businessId, err: ownerErr,
      });
    }
  }

  // 4. Generate QR PNGs for branches.
  if (branchId) {
    const branchRef = bizRef.collection("branches").doc(branchId);
    const branchSnap = await branchRef.get();
    if (branchSnap.exists) {
      try {
        await branchRef.update({
          subscription_status: "active",
          payment_mode: "online",
          activated_at: Timestamp.now(),
          standee_status: STANDEE_STATUS_DEFAULT,
          standee_status_updated_at: Timestamp.now(),
        });
      } catch (e) {
        logger.warn("handleSuccessfulPayment: failed updating branch status", {businessId, branchId, error: e});
      }
      try {
        await buildQrForBranch(businessId, branchId, branchRef);
        await buildPlainQrForBranch(businessId, branchId, branchRef);
      } catch (qrErr) {
        logger.error("handleSuccessfulPayment: branch QR failed", {businessId, branchId, qrErr});
      }
    }
  } else {
    try {
      const branchesSnap = await bizRef.collection("branches").get();
      logger.info("handleSuccessfulPayment: activating branches and generating QR", {
        businessId, branchCount: branchesSnap.size,
      });
      for (const branchDoc of branchesSnap.docs) {
        try {
          await branchDoc.ref.update({
            subscription_status: "active",
            payment_mode: "online",
            activated_at: Timestamp.now(),
            standee_status: STANDEE_STATUS_DEFAULT,
            standee_status_updated_at: Timestamp.now(),
          });
          logger.info("handleSuccessfulPayment: branch activated & standee initialized", {
            businessId, branchId: branchDoc.id,
          });
        } catch (standeeErr) {
          logger.error("handleSuccessfulPayment: branch activation update failed", {
            businessId, branchId: branchDoc.id, err: standeeErr,
          });
        }

        // Standee QR (branded, print-ready, 4×6 — doc 09 pipeline).
        try {
          const result = await buildQrForBranch(
            businessId,
            branchDoc.id,
            branchDoc.ref
          );
          logger.info("handleSuccessfulPayment: standee QR generated", {
            businessId, branchId: branchDoc.id, qrPath: result.qrStoragePath,
          });
        } catch (branchErr) {
          logger.error("handleSuccessfulPayment: standee QR generation failed for branch", {
            businessId, branchId: branchDoc.id, err: branchErr,
          });
        }

        // Change 1: Plain printable QR (instant digital deliverable).
        try {
          const plainResult = await buildPlainQrForBranch(
            businessId,
            branchDoc.id,
            branchDoc.ref
          );
          logger.info("handleSuccessfulPayment: plain QR generated", {
            businessId, branchId: branchDoc.id, path: plainResult.plainQrStoragePath,
          });
        } catch (plainErr) {
          logger.error("handleSuccessfulPayment: plain QR generation failed for branch", {
            businessId, branchId: branchDoc.id, err: plainErr,
          });
        }
      }
    } catch (err) {
      logger.error("handleSuccessfulPayment: failed to read branches for QR generation", {
        businessId, err,
      });
    }
  }
}

// ---------------------------------------------------------------------------
// renewalLifecycle  (scheduled — daily)
// ---------------------------------------------------------------------------

/**
 * Daily scheduled function that enforces the subscription state machine.
 *
 * State transitions (doc 05):
 *   "active"       → "grace_period"  when renewal_date ≤ now
 *                                    (30-day grace window opens)
 *   "grace_period" → "deleted"       when grace_period_ends ≤ now
 *                                    (data cleaned up)
 *
 * Deletion scope:
 *   ✓ businesses/{id}/branches (all branch docs)
 *   ✓ scan_logs referencing those branches
 *   ✓ businesses/{id} (the business doc itself)
 *   ✗ commission_records — NEVER deleted (financial audit trail, per doc 05/06)
 *
 * Uses batched writes (max 500 operations per batch) to avoid hitting limits.
 */
export const renewalLifecycle = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    maxInstances: 1,
  },
  async () => {
    logger.info("renewalLifecycle: starting run");
    const db = getFirestore();
    const now = Timestamp.now();

    logger.info("renewalLifecycle: starting run", {
      timestamp: now.toDate().toISOString(),
    });

    // ── Pass 1: active → grace_period ────────────────────────────────────
    {
      const overdueQuery = db
        .collection("businesses")
        .where("subscription_status", "==", "active")
        .where("renewal_date", "<=", now);

      const overdueSnap = await overdueQuery.get();
      logger.info("renewalLifecycle: active → grace_period candidates", {
        count: overdueSnap.size,
      });

      // Process in batches of 500.
      const chunks = chunkArray(overdueSnap.docs, 500);
      for (const chunk of chunks) {
        const batch = db.batch();
        for (const doc of chunk) {
          const data = doc.data() as {renewal_date?: Timestamp};
          const renewalDate =
            data.renewal_date?.toDate() ?? now.toDate();
          const gracePeriodEnds = addDays(renewalDate, GRACE_PERIOD_DAYS);

          batch.update(doc.ref, {
            subscription_status: "grace_period",
            grace_period_ends:
              Timestamp.fromDate(gracePeriodEnds),
          });

          logger.info("renewalLifecycle: grace_period set", {
            businessId: doc.id,
            gracePeriodEnds: gracePeriodEnds.toISOString(),
          });
        }
        await batch.commit();
      }
    }

    // ── Pass 2: grace_period → deleted ───────────────────────────────────
    {
      const expiredQuery = db
        .collection("businesses")
        .where("subscription_status", "==", "grace_period")
        .where("grace_period_ends", "<=", now);

      const expiredSnap = await expiredQuery.get();
      logger.info("renewalLifecycle: grace_period → deleted candidates", {
        count: expiredSnap.size,
      });

      for (const bizDoc of expiredSnap.docs) {
        await deleteBusiness(db, bizDoc.id, bizDoc.ref);
      }
    }

    logger.info("renewalLifecycle: run complete");
  }
);

// ---------------------------------------------------------------------------
// cleanupAbandonedDrafts  (scheduled — daily)
// ---------------------------------------------------------------------------

/**
 * Daily cleanup of pending_payment businesses older than ABANDONED_DRAFT_AGE_HOURS.
 *
 * Deletes:
 *   ✓ businesses/{id}/branches (all branch subdocs)
 *   ✓ businesses/{id} itself
 *
 * Does NOT delete:
 *   ✗ commission_records — a draft never generates one; nothing to delete.
 *   ✗ active / grace_period / deleted businesses — query-level filter.
 *
 * Age threshold is the ABANDONED_DRAFT_AGE_HOURS constant — change it there only.
 */
export const cleanupAbandonedDrafts = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    maxInstances: 1,
  },
  async () => {
    logger.info("cleanupAbandonedDrafts: starting run");
    const db = getFirestore();
    const now = new Date();
    const cutoff = new Date(
      now.getTime() - ABANDONED_DRAFT_AGE_HOURS * 60 * 60 * 1000
    );
    const cutoffTs = Timestamp.fromDate(cutoff);

    // Query: pending_payment AND created_at older than cutoff.
    // Requires a Firestore composite index on (subscription_status, created_at).
    const draftsSnap = await db
      .collection("businesses")
      .where("subscription_status", "==", "pending_payment")
      .where("created_at", "<=", cutoffTs)
      .get();

    logger.info("cleanupAbandonedDrafts: drafts eligible for deletion", {
      count: draftsSnap.size,
      cutoff: cutoff.toISOString(),
    });

    for (const bizDoc of draftsSnap.docs) {
      // Reuse deleteBusiness (already handles branches + scan_logs).
      await deleteBusiness(db, bizDoc.id, bizDoc.ref);
      logger.info("cleanupAbandonedDrafts: deleted draft", {businessId: bizDoc.id});
    }

    logger.info("cleanupAbandonedDrafts: run complete", {
      deleted: draftsSnap.size,
    });
  }
);

// ---------------------------------------------------------------------------
// deleteBusiness — deletes a business and all related data (except commissions)
// ---------------------------------------------------------------------------

/**
 * Deletes a business document and all associated data.
 *
 * Deleted:
 *   - businesses/{id}/branches (all documents in subcollection)
 *   - scan_logs where branch_id is in the business's branches
 *   - businesses/{id} itself
 *
 * NOT deleted:
 *   - commission_records — financial audit trail, must be kept permanently.
 *
 * @param {object} db - Firestore instance.
 * @param {string} businessId - The business document ID.
 * @param {object} bizRef - Reference to the business doc.
 */
async function deleteBusiness(
  db: Firestore,
  businessId: string,
  bizRef: DocumentReference
): Promise<void> {
  logger.info("deleteBusiness: starting deletion", {businessId});

  // 1. Fetch all branch IDs before deleting anything.
  const branchesSnap = await bizRef.collection("branches").get();
  const branchIds = branchesSnap.docs.map((d) => d.id);

  // 2. Delete scan_logs for each branch (in chunks — Firestore `in` max 30).
  if (branchIds.length > 0) {
    const branchChunks = chunkArray(branchIds, 30);
    for (const branchChunk of branchChunks) {
      const scanLogsSnap = await db
        .collection("scan_logs")
        .where("branch_id", "in", branchChunk)
        .get();

      const scanLogChunks = chunkArray(scanLogsSnap.docs, 500);
      for (const chunk of scanLogChunks) {
        const batch = db.batch();
        for (const doc of chunk) {
          batch.delete(doc.ref);
        }
        await batch.commit();
      }
      logger.info("deleteBusiness: scan_logs deleted", {
        businessId,
        branchChunk,
        count: scanLogsSnap.size,
      });
    }
  }

  // 3. Delete all branch documents.
  if (branchesSnap.docs.length > 0) {
    const branchChunks = chunkArray(branchesSnap.docs, 500);
    for (const chunk of branchChunks) {
      const batch = db.batch();
      for (const doc of chunk) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }
    logger.info("deleteBusiness: branches deleted", {
      businessId,
      count: branchesSnap.docs.length,
    });
  }

  // 4. Delete the business document itself.
  await bizRef.delete();

  logger.info("deleteBusiness: completed", {businessId});
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

/**
 * Splits an array into chunks of at most `size` elements.
 * @param {Array} arr - The source array.
 * @param {number} size - Maximum chunk size.
 * @return {Array}
 */
function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

// ---------------------------------------------------------------------------
// resendPaymentLink  (callable — Change 3)
// ---------------------------------------------------------------------------

/**
 * Creates a fresh Razorpay Payment Link for a pending_payment draft business,
 * emails it to the business owner via the notifications service, and returns
 * the short_url so the employee can share it (WhatsApp, copy).
 *
 * Design decisions:
 *   - Uses Razorpay Payment Links API (not Orders) so the result is a
 *     shareable short URL, not an order ID.
 *   - Payment completion still goes through the existing razorpayWebhook
 *     (payment.captured event) — NO second activation path is added.
 *   - Only valid for pending_payment businesses. Calling on active/grace
 *     businesses is rejected with failed-precondition.
 *
 * Input:  { businessId: string }
 * Output: { shortUrl: string, paymentLinkId: string }
 *
 * Requires Auth (any role). Requires RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET.
 */
export const resendPaymentLink = onCall(
  {
    secrets: [razorpayKeyId, razorpayKeySecret],
    maxInstances: 10,
    region: "asia-south1",
  },
  async (request) => {
    requireAuth(request.auth);

    const {businessId} = request.data as {businessId?: unknown};
    if (typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`businessId` must be a non-empty string."
      );
    }

    const db = admin.firestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const bizSnap = await bizRef.get();

    if (!bizSnap.exists) {
      throw new HttpsError("not-found", `Business '${businessId}' not found.`);
    }

    const bizData = bizSnap.data() as Record<string, unknown>;
    const subscriptionStatus = bizData["subscription_status"] as string | undefined;

    // Only allowed for pending_payment drafts.
    if (subscriptionStatus !== "pending_payment") {
      throw new HttpsError(
        "failed-precondition",
        `Business '${businessId}' is not in pending_payment status ` +
        `(current: ${subscriptionStatus}). Payment link resend is only ` +
        "for businesses awaiting their initial payment."
      );
    }

    const ownerEmail = bizData["owner_email"] as string | undefined;
    const ownerName = bizData["owner_name"] as string | undefined ?? "Business Owner";
    const brandName = bizData["brand_name"] as string | undefined ?? "your business";

    if (!ownerEmail) {
      throw new HttpsError(
        "not-found",
        "Business owner_email is not set. Cannot send payment link."
      );
    }

    // ── Create Razorpay Payment Link ─────────────────────────────────────────
    const branchesSnap = await bizRef.collection("branches").get();
    const branchCount = Math.max(branchesSnap.size, 1);
    const totalAmountPaise = branchCount * SETUP_FEE_PAISE;

    const razorpay = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });

    let paymentLink: {id: string; short_url: string};
    try {
      paymentLink = await (razorpay as unknown as {
        paymentLink: {
          create: (opts: Record<string, unknown>) => Promise<{id: string; short_url: string}>;
        };
      }).paymentLink.create({
        amount: totalAmountPaise,
        currency: "INR",
        description: branchCount > 1 ?
          `Enrollment setup fee (${branchCount} locations) — ${brandName}` :
          `Enrollment setup fee — ${brandName}`,
        notes: {
          businessId,
          type: "setup_fee",
          branchCount: String(branchCount),
        },
        notify: {sms: false, email: false},
        callback_method: "get",
      });
    } catch (err) {
      logger.error("resendPaymentLink: Razorpay paymentLink.create failed", {
        err, businessId,
      });
      throw new HttpsError(
        "internal",
        "Failed to create payment link. Please try again."
      );
    }

    // Persist the payment link on the business doc so the panel can display it.
    await bizRef.update({
      last_payment_link_url: paymentLink.short_url,
      last_payment_link_id: paymentLink.id,
      last_payment_link_created_at: Timestamp.now(),
    });

    // ── Email the payment link to the owner ──────────────────────────────────
    // Reuses the sendPaymentLinkEmail helper exported by notifications.ts.
    // Same Brevo email + Firestore notifications/{id} infrastructure.
    try {
      await sendPaymentLinkEmail({
        ownerEmail,
        ownerName,
        brandName,
        paymentLinkUrl: paymentLink.short_url,
        businessId,
      });
    } catch (emailErr) {
      // Email failure is non-fatal — the link is still returned to the
      // employee who can share it manually via WhatsApp/copy.
      logger.error("resendPaymentLink: email send failed (non-fatal)", {
        businessId, err: emailErr,
      });
    }

    logger.info("resendPaymentLink: complete", {
      businessId,
      paymentLinkId: paymentLink.id,
      shortUrl: paymentLink.short_url,
      callerUid: request.auth?.uid,
    });

    return {
      shortUrl: paymentLink.short_url,
      paymentLinkId: paymentLink.id,
    };
  }
);

/**
 * Creates a Razorpay order for the ₹1999 one-time setup fee for a specific branch.
 *
 * Input:  { businessId: string, branchId: string }
 * Output: { orderId: string, amount: number, currency: string, keyId: string }
 */
export const createBranchOrder = onCall(
  {
    secrets: [razorpayKeyId, razorpayKeySecret],
    maxInstances: 10,
    region: "asia-south1",
  },
  async (request) => {
    requireAuth(request.auth);

    const {businessId, branchId} = request.data as {
      businessId?: unknown;
      branchId?: unknown;
    };
    if (typeof businessId !== "string" || businessId.trim().length === 0 ||
        typeof branchId !== "string" || branchId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`businessId` and `branchId` must be non-empty strings."
      );
    }

    const db = admin.firestore();
    const branchRef = db
      .collection("businesses")
      .doc(businessId)
      .collection("branches")
      .doc(branchId);
    const branchSnap = await branchRef.get();
    if (!branchSnap.exists) {
      throw new HttpsError("not-found", `Branch '${branchId}' not found.`);
    }

    const razorpay = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });

    let order: {id: string; amount: number; currency: string};
    try {
      order = await razorpay.orders.create({
        amount: SETUP_FEE_PAISE,
        currency: "INR",
        receipt: `${businessId}_${branchId}`,
        notes: {
          businessId,
          branchId,
          type: "branch_setup_fee",
        },
      }) as {id: string; amount: number; currency: string};
    } catch (err) {
      logger.error("Razorpay orders.create for branch failed", {err, businessId, branchId});
      throw new HttpsError(
        "internal",
        "Failed to create branch payment order. Please try again."
      );
    }

    logger.info("createBranchOrder: order created", {
      orderId: order.id,
      businessId,
      branchId,
      callerUid: request.auth?.uid,
    });

    return {
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      keyId: razorpayKeyId.value(),
    };
  }
);

/**
 * Creates a Razorpay Payment Link for a pending_payment branch (₹1999)
 * and returns the short_url.
 */
export const resendBranchPaymentLink = onCall(
  {
    secrets: [razorpayKeyId, razorpayKeySecret],
    maxInstances: 10,
    region: "asia-south1",
  },
  async (request) => {
    requireAuth(request.auth);

    const {businessId, branchId} = request.data as {
      businessId?: unknown;
      branchId?: unknown;
    };
    if (typeof businessId !== "string" || businessId.trim().length === 0 ||
        typeof branchId !== "string" || branchId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`businessId` and `branchId` must be non-empty strings."
      );
    }

    const db = admin.firestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const branchRef = bizRef.collection("branches").doc(branchId);

    const [bizSnap, branchSnap] = await Promise.all([bizRef.get(), branchRef.get()]);

    if (!bizSnap.exists || !branchSnap.exists) {
      throw new HttpsError("not-found", "Business or Branch not found.");
    }

    const bizData = bizSnap.data() as Record<string, unknown>;
    const branchData = branchSnap.data() as Record<string, unknown>;

    const ownerEmail = bizData["owner_email"] as string | undefined;
    const ownerName = (bizData["owner_name"] as string | undefined) ?? "Business Owner";
    const brandName = (bizData["brand_name"] as string | undefined) ?? "Business";
    const branchName = (branchData["branch_name"] as string | undefined) ?? "Branch";

    if (!ownerEmail) {
      throw new HttpsError(
        "not-found",
        "Business owner_email is not set. Cannot send payment link."
      );
    }

    const razorpay = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });

    let paymentLink: {id: string; short_url: string};
    try {
      paymentLink = await (razorpay as unknown as {
        paymentLink: {
          create: (opts: Record<string, unknown>) => Promise<{id: string; short_url: string}>;
        };
      }).paymentLink.create({
        amount: SETUP_FEE_PAISE,
        currency: "INR",
        description: `Setup fee for ${brandName} (${branchName})`,
        notes: {
          businessId,
          branchId,
          type: "branch_setup_fee",
        },
        customer: {
          name: ownerName,
          email: ownerEmail,
        },
        notify: {
          sms: false,
          email: true,
        },
        reminder_enable: true,
      });
    } catch (err) {
      logger.error("resendBranchPaymentLink: Razorpay paymentLink.create failed", {
        businessId, branchId, err,
      });
      throw new HttpsError(
        "internal",
        "Failed to generate payment link. Please try again."
      );
    }

    try {
      await sendPaymentLinkEmail({
        ownerEmail,
        ownerName,
        brandName: `${brandName} (${branchName})`,
        paymentLinkUrl: paymentLink.short_url,
        businessId,
      });
    } catch (emailErr) {
      logger.error("resendBranchPaymentLink: email send failed (non-fatal)", {
        businessId, branchId, err: emailErr,
      });
    }

    return {
      shortUrl: paymentLink.short_url,
      paymentLinkId: paymentLink.id,
    };
  }
);

/**
 * Callable function to provision or re-provision an owner Firebase Auth account.
 */
export const provisionOwner = onCall(
  {region: "asia-south1"},
  async (request) => {
    requireAuth(request.auth);
    const {businessId} = request.data as { businessId?: string };
    if (!businessId) {
      throw new HttpsError("invalid-argument", "businessId is required.");
    }
    const db = getFirestore();
    const bizSnap = await db.collection("businesses").doc(businessId).get();
    if (!bizSnap.exists) {
      throw new HttpsError("not-found", "Business not found.");
    }
    const bizData = bizSnap.data() as { owner_email?: string; owner_name?: string };
    if (!bizData.owner_email) {
      throw new HttpsError("failed-precondition", "Business has no owner_email.");
    }
    const ownerUid = await provisionOwnerAccount(
      db,
      businessId,
      bizData.owner_email,
      bizData.owner_name
    );
    return {success: true, ownerUid};
  }
);

