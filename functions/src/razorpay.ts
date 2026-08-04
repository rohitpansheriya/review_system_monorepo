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
 *
 * ─── HTTP Function ─────────────────────────────────────────────────────────
 *   razorpayWebhook    — Receives Razorpay webhook events. Verifies
 *                        HMAC-SHA256 signature before processing. On success:
 *                          • Updates businesses/{id}: subscription_status →
 *                            "active", renewal_date extended by 1 year.
 *                          • Creates commission_records (online / verified).
 *
 * ─── Scheduled Function (daily) ────────────────────────────────────────────
 *   renewalLifecycle   — Enforces the subscription state machine:
 *                          active  →  grace_period (renewal_date passed)
 *                          grace_period → deleted  (grace_period_ends passed)
 *                        NEVER deletes commission_records (financial audit).
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

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Setup fee in paise (₹1999 × 100). */
const SETUP_FEE_PAISE = 199900;

/** Annual renewal fee in paise (₹999 × 100) — for commission records. */
const RENEWAL_FEE_PAISE = 99900;

/** Grace period duration in days after renewal_date passes without payment. */
const GRACE_PERIOD_DAYS = 30;

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

    const razorpay = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });

    let order: {id: string; amount: number; currency: string};
    try {
      order = await razorpay.orders.create({
        amount: SETUP_FEE_PAISE,
        currency: "INR",
        // receipt is used by the webhook to map payment → business.
        receipt: businessId,
        notes: {
          businessId,
          type: "setup_fee",
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
 * Processes a confirmed payment:
 *   - Determines businessId from the event payload.
 *   - Updates subscription_status → "active", extends renewal_date + 1 year.
 *   - Creates a commission_records document
 *     (payment_mode: "online", status: "verified").
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
    enrolled_by?: string;
    subscription_status?: string;
    renewal_date?: Timestamp;
  };

  const now = new Date();
  // Extend from the existing renewal_date if it is in the future; otherwise
  // extend from now (covers the case where renewal_date has already passed).
  const baseDate =
    bizData.renewal_date && bizData.renewal_date.toDate() > now ?
      bizData.renewal_date.toDate() :
      now;

  const newRenewalDate = addYears(baseDate, 1);

  // ── Firestore writes ─────────────────────────────────────────────────────
  const batch = db.batch();

  // 1. Update business document.
  batch.update(bizRef, {
    subscription_status: "active",
    renewal_date: Timestamp.fromDate(newRenewalDate),
    grace_period_ends: FieldValue.delete(),
  });

  // 2. Create commission_records entry.
  //    employee_id comes from enrolled_by; falls back to "admin" if unset.
  const commissionRef = db.collection("commission_records").doc();
  batch.set(commissionRef, {
    employee_id: bizData.enrolled_by ?? "admin",
    business_id: businessId,
    amount: amountPaise / 100, // store in rupees
    payment_mode: "online",
    status: "verified",
    date_claimed: Timestamp.fromDate(now),
    date_verified: Timestamp.fromDate(now),
  });

  await batch.commit();

  logger.info("handleSuccessfulPayment: Firestore updated", {
    businessId,
    newRenewalDate: newRenewalDate.toISOString(),
    eventName,
    amountRupees: amountPaise / 100,
  });
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
