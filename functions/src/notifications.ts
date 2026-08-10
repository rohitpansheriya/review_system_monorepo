/**
 * notifications.ts
 *
 * Cloud Functions for the Notifications System (doc 08).
 *
 * ─── Scheduled Functions ───────────────────────────────────────────────
 *   sendRenewalReminders — daily; emails owner + employee at the
 *     30 / 15 / 7 / 1 day windows before each business's renewal_date.
 *   sendAdminDigest — weekly (Mon 09:00 IST); one summary email to admin
 *     listing all businesses renewing in the next 30 days.
 *
 * ─── Callable Function ─────────────────────────────────────────────────
 *   sendCashPaymentVerification — doc 06 fraud prevention;
 *     asks the business owner to confirm a cash payment.
 *     Reuses the same email + notifications infrastructure.
 *
 * Email delivery: Brevo Transactional API v3 (native fetch, Node 24).
 * Firestore writes: notifications/{id}
 *   { recipient, recipient_name, recipient_role, type, business_id,
 *     message, subject, sent_at, read: false }
 *   This collection is what doc 02's dashboard banner will read.
 *
 * RULE 2 (pending_payment draft isolation):
 *   Both scheduled functions query with:
 *     .where("subscription_status", "in", ["active", "grace_period"])
 *   This is a QUERY-LEVEL filter — pending_payment docs (which have no
 *   renewal_date) are NEVER returned and NEVER processed. The null
 *   renewal_date cannot cause an error if the doc is never read.
 *
 * TODO(doc-02): Add FCM Web Push alongside email when building the
 *   owner dashboard. This file intentionally omits push notifications
 *   — deferred per AGENTS.md implementation order.
 *
 * See: docs/08-notifications-system.md
 *      docs/06-commission-tracking.md
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {brevoApiKey, brevoSenderEmail, adminEmail} from "./secrets.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SendBrevoOpts {
  to: string;
  toName: string;
  subject: string;
  html: string;
  text: string;
}

interface NotifRecipient {
  email: string;
  name: string;
  role: "owner" | "employee" | "admin";
  fcmToken: string | null;
}

interface SendNotificationOpts {
  to: NotifRecipient;
  subject: string;
  html: string;
  text: string;
  type: string;
  businessId: string | null;
}

interface WriteNotificationData {
  recipient: string;
  recipientName: string;
  recipientRole: string;
  type: string;
  businessId: string | null;
  message: string;
  subject: string;
}

/** Options for sendPaymentLinkEmail (Change 3 — resend payment link). */
interface SendPaymentLinkEmailOpts {
  ownerEmail: string;
  ownerName: string;
  brandName: string;
  paymentLinkUrl: string;
  businessId: string;
}

// ---------------------------------------------------------------------------
// Internal: Brevo email sender
// ---------------------------------------------------------------------------

/**
 * Sends one transactional email via Brevo API v3.
 * Throws on HTTP non-2xx or missing config.
 * @param {SendBrevoOpts} opts - Email options.
 * @return {Promise<void>}
 */
async function sendBrevoEmail(opts: SendBrevoOpts): Promise<void> {
  const apiKey = brevoApiKey.value();
  const sender = brevoSenderEmail.value();
  if (!apiKey || !sender) {
    throw new Error(
      "Missing BREVO_API_KEY or BREVO_SENDER_EMAIL — " +
      "ensure both are configured before sending email."
    );
  }
  const body = JSON.stringify({
    sender: {name: "Review System", email: sender},
    to: [{email: opts.to, name: opts.toName}],
    subject: opts.subject,
    htmlContent: opts.html,
    textContent: opts.text,
  });
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      "api-key": apiKey,
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    body,
  });
  if (!res.ok) {
    const errText = await res.text().catch(() => "(unreadable)");
    throw new Error(`Brevo API ${res.status}: ${errText.slice(0, 200)}`);
  }
}

// ---------------------------------------------------------------------------
// Internal: Firestore notification writer
// ---------------------------------------------------------------------------

/**
 * Writes one document to notifications/{auto-id}.
 * The doc is immediately readable by the dashboard banner (doc 02).
 * @param {WriteNotificationData} data - Notification fields.
 * @return {Promise<void>}
 */
async function writeNotification(data: WriteNotificationData): Promise<void> {
  const db = getFirestore();
  await db.collection("notifications").add({
    recipient: data.recipient,
    recipient_name: data.recipientName,
    recipient_role: data.recipientRole,
    type: data.type,
    business_id: data.businessId,
    message: data.message,
    subject: data.subject,
    sent_at: Timestamp.now(),
    read: false,
  });
}

/**
 * Unified notification service (doc 08).
 *
 * Dispatch order (each channel is independently error-isolated):
 *   1. Firestore `notifications/{id}` write — always first so dashboard
 *      banner shows even if email / push fail.
 *   2. Brevo transactional email — best-effort.
 *   3. FCM Web Push — best-effort; silently skipped if fcmToken is null/absent
 *      (token is stored by the Flutter panel at login — doc 02/03).
 *
 * This is the single function all notification types must call.
 * New notification templates (doc 06 cash verification, doc 02 dashboard,
 * future types) add a new NotifType + template; they reuse this dispatcher.
 *
 * @param {SendNotificationOpts} opts - Notification options.
 * @return {Promise<void>}
 */
async function sendNotification(opts: SendNotificationOpts): Promise<void> {
  const {to, subject, html, text, type, businessId} = opts;

  // ── 1. Firestore write (always first — dashboard banner) ──────────
  try {
    await writeNotification({
      recipient: to.email,
      recipientName: to.name,
      recipientRole: to.role,
      type,
      businessId,
      message: text,
      subject,
    });
  } catch (err) {
    logger.error("sendNotification: Firestore write failed", {
      role: to.role, type, err,
    });
    // Non-fatal — continue to attempt other channels.
  }

  // ── 2. Brevo email ────────────────────────────────────────────────
  try {
    await sendBrevoEmail({
      to: to.email,
      toName: to.name,
      subject,
      html,
      text,
    });
    logger.info("sendNotification: email sent", {role: to.role, type});
  } catch (err) {
    logger.error("sendNotification: Brevo email failed", {
      role: to.role, type, err,
    });
  }

  // ── 3. FCM Web Push ───────────────────────────────────────────────
  if (to.fcmToken) {
    try {
      await getMessaging().send({
        token: to.fcmToken,
        notification: {
          title: subject,
          body: text.length > 200 ? text.slice(0, 197) + "..." : text,
        },
        data: {
          notif_type: type,
          business_id: businessId ?? "",
        },
        android: {priority: "high"},
        apns: {payload: {aps: {"content-available": 1}}},
      });
      logger.info("sendNotification: FCM push sent", {role: to.role, type});
    } catch (err) {
      // FCM failures are non-fatal — email + Firestore already sent.
      logger.warn("sendNotification: FCM push failed", {role: to.role, type, err});
    }
  } else {
    logger.debug("sendNotification: no FCM token — push skipped", {
      role: to.role, type,
    });
  }
}

// ---------------------------------------------------------------------------
// Internal: idempotency guard
// ---------------------------------------------------------------------------

/**
 * Returns true if a notification of this type was already sent for this
 * business within the last 20 hours (prevents double-sends on retry).
 * @param {string} businessId - Firestore business document ID.
 * @param {string} type - Notification type string.
 * @return {Promise<boolean>}
 */
async function isAlreadyNotified(
  businessId: string,
  type: string
): Promise<boolean> {
  const db = getFirestore();
  const cutoff = new Date(Date.now() - 20 * 60 * 60 * 1000);
  const snap = await db
    .collection("notifications")
    .where("business_id", "==", businessId)
    .where("type", "==", type)
    .where("sent_at", ">=", Timestamp.fromDate(cutoff))
    .limit(1)
    .get();
  return !snap.empty;
}

// ---------------------------------------------------------------------------
// Internal: Email HTML templates
// ---------------------------------------------------------------------------

function ownerReminderHtml(brandName: string, daysDiff: number): string {
  const colour = daysDiff <= 7 ? "#f87171" : "#7c6cfc";
  const daysLabel = daysDiff === 1 ? "1 day" : `${daysDiff} days`;
  return [
    "<div style=\"font-family:sans-serif;",
    "max-width:480px;margin:0 auto;\">",
    `<h2 style="color:${colour};">`,
    `  Subscription expires in ${daysLabel}`,
    "</h2>",
    "<p>Dear " + brandName + " owner,</p>",
    "<p>Your review page subscription is due for renewal in ",
    `<strong>${daysLabel}</strong>. `,
    "Pay <strong>₹999</strong> to keep your review page ",
    "active and continue collecting customer reviews.</p>",
    "<p>Log in to your dashboard to renew now.</p>",
    "<hr/>",
    "<p style=\"color:#888;font-size:12px;\">",
    "  Review System — automated renewal notice",
    "</p>",
    "</div>",
  ].join("\n");
}

function employeeReminderHtml(brandName: string, daysDiff: number): string {
  const daysLabel = daysDiff === 1 ? "1 day" : `${daysDiff} days`;
  return [
    "<div style=\"font-family:sans-serif;",
    "max-width:480px;margin:0 auto;\">",
    "<h2>Client Renewal Reminder</h2>",
    `<p><strong>${brandName}</strong> — subscription expires `,
    `in <strong>${daysLabel}</strong>.</p>`,
    "<p>Please follow up with the business owner to ensure they ",
    "renew before the subscription lapses.</p>",
    "<hr/>",
    "<p style=\"color:#888;font-size:12px;\">",
    "  Review System — automated employee notice",
    "</p>",
    "</div>",
  ].join("\n");
}

function adminDigestHtml(
  rows: Array<{name: string; renewal: string; days: number; status: string}>
): string {
  const trs = rows.map((r) => `<tr>
      <td style="padding:6px 10px;">${r.name}</td>
      <td style="padding:6px 10px;">${r.renewal}</td>
      <td style="padding:6px 10px;">${r.days} days</td>
      <td style="padding:6px 10px;">${r.status}</td>
    </tr>`).join("\n");
  return [
    "<div style=\"font-family:sans-serif;",
    "max-width:700px;margin:0 auto;\">",
    "<h2>Weekly Renewal Digest</h2>",
    `<p>${rows.length} business(es) renewing in the next 30 days:</p>`,
    "<table border=\"1\" cellpadding=\"0\" cellspacing=\"0\" ",
    "width=\"100%\" style=\"border-collapse:collapse;\">",
    "  <thead><tr style=\"background:#f3f3f3;\">",
    "    <th style=\"padding:8px 10px;\">Business</th>",
    "    <th style=\"padding:8px 10px;\">Renewal Date</th>",
    "    <th style=\"padding:8px 10px;\">Days Left</th>",
    "    <th style=\"padding:8px 10px;\">Status</th>",
    "  </tr></thead>",
    "  <tbody>",
    trs,
    "  </tbody>",
    "</table>",
    "<hr/>",
    "<p style=\"color:#888;font-size:12px;\">",
    "  Review System — weekly admin digest",
    "</p>",
    "</div>",
  ].join("\n");
}

// ---------------------------------------------------------------------------
// sendRenewalReminders — daily scheduled
// ---------------------------------------------------------------------------

/**
 * Daily scheduled function.
 * At the 30 / 15 / 7 / 1-day windows before each business's renewal_date:
 *   - Emails the business owner (if owner_email is set on the business doc).
 *   - Emails the enrolling/managing employee (if employees/{id}.contact
 *     contains an email address).
 * Writes one notifications/{id} doc per email sent.
 * Idempotent: skips if already notified within the last 20 hours.
 *
 * RULE 2: Queries with .where("subscription_status", "in", ["active", "grace_period"]).
 * pending_payment drafts have no renewal_date and are NEVER returned by this query.
 *
 * Requires BREVO_API_KEY (secret) and BREVO_SENDER_EMAIL (param).
 */
export const sendRenewalReminders = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Asia/Kolkata",
    secrets: [brevoApiKey],
    maxInstances: 1,
    region: "asia-south1",
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const WINDOWS = [30, 15, 7, 1];
    const MS_PER_DAY = 24 * 60 * 60 * 1000;

    // RULE 2: query-level filter — pending_payment docs never returned.
    const bizSnap = await db
      .collection("businesses")
      .where("subscription_status", "in", ["active", "grace_period"])
      .get();

    logger.info("sendRenewalReminders: checking businesses", {
      count: bizSnap.size,
    });

    for (const bizDoc of bizSnap.docs) {
      const biz = bizDoc.data();
      const renewalTs = biz.renewal_date;
      if (!renewalTs) continue;

      // Guard: skip docs where renewal_date is not a real Firestore Timestamp.
      if (typeof renewalTs.toDate !== "function") {
        logger.warn(
          "sendRenewalReminders: renewal_date is not a Timestamp, skipping",
          {businessId: bizDoc.id, renewalDate: renewalTs}
        );
        continue;
      }

      const daysDiff = Math.round(
        (renewalTs.toDate().getTime() - now.getTime()) / MS_PER_DAY
      );
      if (!WINDOWS.includes(daysDiff)) continue;

      const notifType = `renewal_reminder_${daysDiff}`;
      const brandName = biz.brand_name || bizDoc.id;

      // ── Idempotency ───────────────────────────────────────────────
      const alreadySent = await isAlreadyNotified(bizDoc.id, notifType);
      if (alreadySent) {
        logger.info("sendRenewalReminders: already notified", {
          businessId: bizDoc.id, notifType,
        });
        continue;
      }

      const daysLabel = daysDiff === 1 ? "1 day" : `${daysDiff} days`;

      // ── Owner notification ────────────────────────────────────────
      const ownerEmail = biz.owner_email;
      if (ownerEmail) {
        const subject = daysDiff === 1 ?
          `⚠️ Review page expires tomorrow — ${brandName}` :
          `Renewal in ${daysLabel} — ${brandName}`;
        const plainText =
          `Your review page subscription expires in ${daysLabel}. ` +
          "Pay ₹999 to keep your review page active.";
        await sendNotification({
          to: {
            email: ownerEmail,
            name: brandName,
            role: "owner",
            fcmToken: biz.owner_fcm_token ?? null,
          },
          subject,
          html: ownerReminderHtml(brandName, daysDiff),
          text: plainText,
          type: notifType,
          businessId: bizDoc.id,
        });
      } else {
        logger.warn("sendRenewalReminders: no owner_email — skipping owner", {
          businessId: bizDoc.id,
        });
      }

      // ── Employee notification ─────────────────────────────────────
      const empId = biz.currently_managed_by || biz.enrolled_by;
      if (!empId || empId === "admin") continue;

      try {
        const empSnap = await db.collection("employees").doc(empId).get();
        if (!empSnap.exists) {
          logger.warn("sendRenewalReminders: employee doc missing", {empId});
          continue;
        }
        const emp = empSnap.data() as Record<string, unknown>;
        const empEmail = emp.contact as string || "";
        const empName = emp.name as string || "Employee";
        if (!empEmail.includes("@")) {
          logger.warn(
            "sendRenewalReminders: employee contact is not an email — skipping",
            {empId}
          );
          continue;
        }
        await sendNotification({
          to: {
            email: empEmail,
            name: empName,
            role: "employee",
            fcmToken: (emp.fcm_token as string | null) ?? null,
          },
          subject: `Follow-up: ${brandName} renewal in ${daysLabel}`,
          html: employeeReminderHtml(brandName, daysDiff),
          text:
            `${brandName} subscription expires in ${daysLabel}. ` +
            "Please follow up with the business owner.",
          type: notifType,
          businessId: bizDoc.id,
        });
      } catch (err) {
        logger.error("sendRenewalReminders: employee block failed", {
          businessId: bizDoc.id, empId, err,
        });
      }
    }
    logger.info("sendRenewalReminders: run complete");
  }
);

// ---------------------------------------------------------------------------
// sendAdminDigest — weekly scheduled (Mon 09:00 IST)
// ---------------------------------------------------------------------------

/**
 * Weekly scheduled function (Monday 09:00 IST).
 * Compiles a single digest email to ADMIN_EMAIL listing all businesses
 * whose renewal_date falls within the next 30 days.
 *
 * RULE 2: Queries with .where("subscription_status", "in", ["active", "grace_period"]).
 * pending_payment drafts are excluded at the query level.
 *
 * Requires BREVO_API_KEY (secret), BREVO_SENDER_EMAIL and ADMIN_EMAIL (params).
 */
export const sendAdminDigest = onSchedule(
  {
    // 03:30 UTC = 09:00 IST; run on Monday
    schedule: "30 3 * * 1",
    timeZone: "Asia/Kolkata",
    secrets: [brevoApiKey],
    maxInstances: 1,
    region: "asia-south1",
  },
  async () => {
    const toEmail = adminEmail.value();
    if (!toEmail) {
      logger.warn("sendAdminDigest: ADMIN_EMAIL param not set — skipping");
      return;
    }

    const db = getFirestore();
    const now = new Date();
    const MS_PER_DAY = 24 * 60 * 60 * 1000;

    // RULE 2: query-level filter — pending_payment docs never returned.
    const snap = await db
      .collection("businesses")
      .where("subscription_status", "in", ["active", "grace_period"])
      .get();

    const rows = snap.docs
      .map((doc) => {
        const d = doc.data();
        const renewalRaw = d.renewal_date;
        const isTimestamp =
          renewalRaw && typeof renewalRaw.toDate === "function";
        if (!isTimestamp) {
          logger.warn("sendAdminDigest: renewal_date is not a Timestamp, skipping", {
            businessId: doc.id, renewalDate: renewalRaw,
          });
          return null;
        }
        const renewal = renewalRaw.toDate() as Date;
        const days = Math.round(
          (renewal.getTime() - now.getTime()) / MS_PER_DAY
        );
        return {
          id: doc.id,
          name: d.brand_name as string || doc.id,
          renewal: renewal.toLocaleDateString("en-IN"),
          days,
          status: d.subscription_status as string || "—",
        };
      })
      .filter(
        (r): r is NonNullable<typeof r> =>
          r !== null && r.days >= 0 && r.days <= 30
      )
      .sort((a, b) => a.days - b.days);

    logger.info("sendAdminDigest: upcoming renewals", {count: rows.length});

    if (rows.length === 0) {
      logger.info("sendAdminDigest: no upcoming renewals — skip");
      return;
    }

    const subject = `Weekly Renewal Digest — ${rows.length} upcoming`;
    const plainText = rows
      .map((r) => `${r.name}: ${r.renewal} (${r.days} days) — ${r.status}`)
      .join("\n");

    await sendBrevoEmail({
      to: toEmail,
      toName: "Admin",
      subject,
      html: adminDigestHtml(rows),
      text: plainText,
    });

    await writeNotification({
      recipient: toEmail,
      recipientName: "Admin",
      recipientRole: "admin",
      type: "admin_weekly_digest",
      businessId: null,
      message: `${rows.length} business renewal(s) in the next 30 days.`,
      subject,
    });

    logger.info("sendAdminDigest: complete", {count: rows.length});
  }
);

// ---------------------------------------------------------------------------
// sendCashPaymentVerification — onCall (doc 06)
// ---------------------------------------------------------------------------

/**
 * Sends a payment confirmation request to a business owner:
 * "Did you pay ₹X in cash to [Employee] on [date]? Yes/No"
 *
 * Called by the admin panel when a commission record is awaiting
 * owner-side verification (doc 06, cash payment fraud prevention).
 * Reuses the same Brevo email + notifications infrastructure.
 *
 * Input:  { commissionRecordId: string }
 * Output: { success: true }
 *
 * Requires Auth. Requires BREVO_API_KEY secret and BREVO_SENDER_EMAIL.
 */
export const sendCashPaymentVerification = onCall(
  {
    secrets: [brevoApiKey],
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Must be signed in to call this function."
      );
    }

    const {commissionRecordId} = (request.data || {}) as {
      commissionRecordId?: string;
    };
    if (!commissionRecordId || !commissionRecordId.trim()) {
      throw new HttpsError(
        "invalid-argument",
        "commissionRecordId is required."
      );
    }

    const db = getFirestore();

    // ── Read commission record ────────────────────────────────────
    const commSnap = await db
      .collection("commission_records")
      .doc(commissionRecordId)
      .get();
    if (!commSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Commission record ${commissionRecordId} not found.`
      );
    }
    const comm = commSnap.data() as Record<string, unknown>;
    if (comm.payment_mode !== "cash") {
      throw new HttpsError(
        "invalid-argument",
        "Verification email is only for cash payments."
      );
    }

    const bizId = comm.business_id as string | undefined;
    const empId = comm.employee_id as string | undefined;
    const amount = comm.amount as number | undefined;
    const dateClaimed = comm.date_claimed as Timestamp | undefined;

    if (!bizId) {
      throw new HttpsError("internal", "Commission record is missing business_id.");
    }

    // ── Read business ─────────────────────────────────────────────
    const bizSnap = await db.collection("businesses").doc(bizId).get();
    const biz = (bizSnap.data() || {}) as Record<string, unknown>;
    const ownerEmail = biz.owner_email as string | undefined;
    if (!ownerEmail) {
      throw new HttpsError(
        "not-found",
        "Business owner_email is not set. " +
        "Store it on the business document at enrollment (doc 03)."
      );
    }

    // ── Read employee ─────────────────────────────────────────────
    let empName = "an employee";
    if (empId) {
      const empSnap = await db.collection("employees").doc(empId).get();
      const en = empSnap.data()?.name;
      if (typeof en === "string" && en.trim()) empName = en.trim();
    }

    // ── Build message ─────────────────────────────────────────────
    const brandName = (biz.brand_name as string) || "your business";
    const amtStr = `₹${(amount || 0).toLocaleString("en-IN")}`;
    const dateStr = dateClaimed ?
      dateClaimed.toDate().toLocaleDateString("en-IN") :
      "recently";

    const subject = `Payment verification required — ${brandName}`;
    const plainText =
      `Did you pay ${amtStr} in cash to ${empName} on ${dateStr}? ` +
      "Please reply YES or NO to confirm.";
    const html = [
      "<div style=\"font-family:sans-serif;",
      "max-width:480px;margin:0 auto;\">",
      "<h2>Payment Verification Request</h2>",
      `<p>Dear ${brandName} owner,</p>`,
      "<p>Our records show a cash payment of ",
      `<strong>${amtStr}</strong> was collected from you by `,
      `<strong>${empName}</strong> on <strong>${dateStr}</strong>.</p>`,
      "<p>Please reply to this email with <strong>YES</strong> if ",
      "this payment was made, or <strong>NO</strong> if it was not. ",
      "This helps us verify that your payment is correctly ",
      "recorded.</p>",
      "<hr/>",
      "<p style=\"color:#888;font-size:12px;\">",
      `  Record: ${commissionRecordId} — `,
      "  Review System automated verification notice",
      "</p>",
      "</div>",
    ].join("\n");

    // ── Send via unified notification service ────────────────────
    const ownerFcmToken =
      (biz.owner_fcm_token as string | null) ?? null;
    await sendNotification({
      to: {
        email: ownerEmail,
        name: brandName,
        role: "owner",
        fcmToken: ownerFcmToken,
      },
      subject,
      html,
      text: plainText,
      type: "cash_payment_verification",
      businessId: bizId,
    });

    logger.info("sendCashPaymentVerification: sent", {
      businessId: bizId,
      commissionRecordId,
    });
    return {success: true};
  }
);

// ---------------------------------------------------------------------------
// sendPaymentLinkEmail — exported helper (Change 3)
// ---------------------------------------------------------------------------

/**
 * Sends a payment link to the business owner by email and writes a Firestore
 * notification document.
 *
 * Called by razorpay.ts:resendPaymentLink after creating the Razorpay Payment
 * Link. Reuses the same Brevo email + sendNotification infrastructure — no
 * new delivery channel is introduced.
 *
 * Exported so razorpay.ts can import it. Not registered as a Cloud Function
 * itself (it is a plain async helper).
 *
 * @param {SendPaymentLinkEmailOpts} opts - Payment link email options.
 * @return {Promise<void>}
 */
export async function sendPaymentLinkEmail(
  opts: SendPaymentLinkEmailOpts
): Promise<void> {
  const {ownerEmail, ownerName, brandName, paymentLinkUrl, businessId} = opts;

  const subject = `Complete your enrollment payment — ${brandName}`;
  const plainText =
    `Your enrollment for ${brandName} is almost complete. ` +
    `Please pay the ₹1999 setup fee to activate your review page: ` +
    `${paymentLinkUrl}`;

  const html = [
    "<div style=\"font-family:sans-serif;max-width:480px;margin:0 auto;\">",
    "<h2 style=\"color:#6C63FF;\">Complete Your Enrollment</h2>",
    `<p>Dear ${ownerName},</p>`,
    `<p>Your enrollment for <strong>${brandName}</strong> is pending payment.`,
    " Pay the <strong>₹1999 one-time setup fee</strong> to activate your",
    " review page and start collecting customer feedback.</p>",
    "<p>",
    `  <a href="${paymentLinkUrl}"`,
    "     style=\"display:inline-block;background:#6C63FF;color:white;",
    "            padding:12px 24px;border-radius:8px;text-decoration:none;",
    "            font-weight:bold;\">",
    "    Pay Now →",
    "  </a>",
    "</p>",
    `<p style="font-size:12px;color:#666;">Or copy this link: ${paymentLinkUrl}</p>`,
    "<hr/>",
    "<p style=\"color:#888;font-size:12px;\">",
    "  Review System — enrollment payment reminder",
    "</p>",
    "</div>",
  ].join("\n");

  await sendNotification({
    to: {
      email: ownerEmail,
      name: ownerName,
      role: "owner",
      fcmToken: null,
    },
    subject,
    html,
    text: plainText,
    type: "resend_payment_link",
    businessId,
  });
}

