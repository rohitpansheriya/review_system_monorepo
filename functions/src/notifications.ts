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
import {getAuth} from "firebase-admin/auth";
import {
  brevoApiKey,
  brevoSenderEmail,
  adminEmail,
  razorpayKeyId,
  razorpayKeySecret,
  reviewDomain,
} from "./secrets.js";
import {generateInvoicePdf} from "./invoiceGenerator.js";
import Razorpay from "razorpay";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SendBrevoOpts {
  to: string;
  toName: string;
  subject: string;
  html: string;
  text: string;
  attachments?: Array<{ name: string; content: string }>;
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
  attachments?: Array<{ name: string; content: string }>;
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
export interface SendPaymentLinkEmailOpts {
  ownerEmail: string;
  ownerName: string;
  brandName: string;
  paymentLinkUrl: string;
  businessId: string;
  amount?: number;
  branchNames?: string[];
  branches?: Array<{name: string; address?: string}>;
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
  const sender = (brevoSenderEmail.value() || process.env.BREVO_SENDER_EMAIL || "noreply@appnexa.co.in").trim();
  if (!apiKey || !sender) {
    logger.error("sendBrevoEmail: Missing BREVO_API_KEY or BREVO_SENDER_EMAIL", {
      hasApiKey: !!apiKey,
      sender,
    });
    throw new Error(
      "Missing BREVO_API_KEY or BREVO_SENDER_EMAIL — " +
      "ensure both are configured before sending email."
    );
  }
  const payload: Record<string, unknown> = {
    sender: {name: "AppNexa Technologies", email: sender},
    replyTo: {name: "AppNexa Support", email: "support@appnexa.co.in"},
    to: [{email: opts.to, name: opts.toName}],
    subject: opts.subject,
    htmlContent: opts.html,
    textContent: opts.text,
  };
  if (opts.attachments && opts.attachments.length > 0) {
    payload.attachment = opts.attachments;
  }
  const body = JSON.stringify(payload);
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
    logger.error("sendBrevoEmail: Brevo API rejected email send", {
      status: res.status,
      error: errText,
      recipient: opts.to,
      subject: opts.subject,
    });
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
      attachments: opts.attachments,
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

function ownerGracePeriodReminderHtml(
  brandName: string,
  daysPassed: number,
  remainingDays: number,
  renewalDateStr: string,
  paymentLinkUrl: string
): string {
  const isFinalDay = remainingDays <= 1;
  const badgeColor = isFinalDay ? "#dc2626" : "#d97706";
  const badgeBg = isFinalDay ? "#fef2f2" : "#fffbeb";
  const badgeBorder = isFinalDay ? "#fecaca" : "#fef3c7";
  const countdownTitle = isFinalDay ? "⚡ FINAL DAY TO RENEW" : `⏳ ${remainingDays} Days Remaining in Grace Period`;

  return [
    "<div style=\"background-color:#f8fafc;padding:30px 15px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1e293b;line-height:1.6;\">",
    "  <div style=\"max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.06);border:1px solid #e2e8f0;\">",
    "    <!-- Brand Header -->",
    "    <div style=\"background:linear-gradient(135deg, #1b3a8c, #2f6bff);padding:24px 28px;text-align:center;\">",
    "      <h1 style=\"color:#ffffff;margin:0;font-size:22px;font-weight:800;letter-spacing:-0.5px;\">AppNexa Technologies</h1>",
    "      <p style=\"color:#cbd5e1;margin:4px 0 0;font-size:13px;font-weight:500;\">Google Review Growth &amp; Counter Standee System</p>",
    "    </div>",
    "    <!-- Alert Banner -->",
    "    <div style=\"background:" + badgeBg + ";border-bottom:1px solid " + badgeBorder + ";padding:14px 28px;display:flex;align-items:center;gap:12px;\">",
    "      <div style=\"font-size:20px;line-height:1;\">⚠️</div>",
    "      <div>",
    "        <div style=\"color:" + badgeColor + ";font-weight:800;font-size:13px;text-transform:uppercase;letter-spacing:0.5px;\">",
    "          Subscription In Grace Period — Day " + daysPassed + " of 30",
    "        </div>",
    "        <p style=\"font-size:15px;margin-top:0;\">Dear <strong>" + brandName + "</strong> Owner,</p>",
    "        <p style=\"font-size:14px;color:#334155;\">",
    "          Your annual subscription for your <strong>AppNexa Google Review Standees &amp; Dashboard</strong> expired on <strong>" + renewalDateStr + "</strong> and is currently in its <strong>30-Day Grace Period</strong>.",
    "        </p>",
    "        <!-- Countdown Box -->",
    "        <div style=\"background:#f8fafc;border:1.5px dashed #cbd5e1;border-radius:12px;padding:18px;margin:20px 0;text-align:center;\">",
    "          <div style=\"font-size:11px;color:#64748b;font-weight:700;text-transform:uppercase;letter-spacing:1px;\">Grace Period Status</div>",
    "          <div style=\"font-size:24px;font-weight:800;color:" + badgeColor + ";margin:6px 0;\">",
    "            " + countdownTitle,
    "          </div>",
    "          <div style=\"font-size:13px;color:#475569;\">",
    "            Renew now for <strong>₹999 / year</strong> to keep your review page &amp; standees fully active.",
    "          </div>",
    "        </div>",
    "        <!-- Penalty Notice Box -->",
    "        <div style=\"background:#fef2f2;border-left:4px solid #ef4444;padding:16px;border-radius:0 8px 8px 0;margin:20px 0;\">",
    "          <div style=\"font-weight:800;color:#991b1b;font-size:13px;margin-bottom:4px;\">",
    "            ⚠️ Critical Notice &amp; Re-Enrollment Penalty Policy:",
    "          </div>",
    "          <div style=\"font-size:13px;color:#7f1d1d;line-height:1.5;\">",
    "            If your subscription is not renewed within the remaining <strong>" + remainingDays + " days</strong> of the grace period, your business review page and standees will be <strong>permanently deactivated and suspended</strong>.",
    "            <br/><br/>",
    "            Once deactivated, you will lose your discounted annual renewal rate (₹999) and <strong>must re-enroll as a new business at the full initial enrollment fee of ₹1,999</strong>.",
    "          </div>",
    "        </div>",
    "        <!-- Direct 1-Click Payment Action Button -->",
    "        <div style=\"text-align:center;margin:30px 0 20px;\">",
    "          <a href=\"" + paymentLinkUrl + "\" style=\"background:linear-gradient(135deg, #10b981, #059669);color:#ffffff;text-decoration:none;padding:15px 36px;font-size:16px;font-weight:800;border-radius:10px;display:inline-block;box-shadow:0 4px 14px rgba(16,185,129,0.4);letter-spacing:0.3px;\">",
    "            💳 Pay ₹999 &amp; Activate Business Now &rarr;",
    "          </a>",
    "          <div style=\"font-size:12px;color:#64748b;margin-top:8px;\">Instant Activation &bull; UPI (GPay, PhonePe, Paytm) / Cards / NetBanking</div>",
    "        </div>",
    "        <hr style=\"border:none;border-top:1px solid #e2e8f0;margin:24px 0;\" />",
    "        <!-- Support Footer -->",
    "        <div style=\"font-size:12px;color:#64748b;line-height:1.6;\">",
    "          <strong>Need help or paying via cash / bank transfer?</strong><br/>",
    "          Call/WhatsApp our support desk at <a href=\"tel:+918866390389\" style=\"color:#1b3a8c;font-weight:bold;text-decoration:none;\">+91 8866390389</a> or email <a href=\"mailto:support@appnexa.co.in\" style=\"color:#1b3a8c;text-decoration:none;\">support@appnexa.co.in</a>.",
    "        </div>",
    "      </div>",
    "    </div>",
    "    <div style=\"background:#f1f5f9;padding:14px 28px;text-align:center;font-size:11px;color:#94a3b8;border-top:1px solid #e2e8f0;\">",
    "      AppNexa Technologies &bull; Surat, Gujarat &bull; Automated Grace Period Alert",
    "    </div>",
    "  </div>",
    "</div>",
  ].join("\n");
}

function employeeGracePeriodReminderHtml(
  brandName: string,
  daysPassed: number,
  remainingDays: number
): string {
  const isFinalDay = remainingDays <= 1;
  const badgeColor = isFinalDay ? "#dc2626" : "#d97706";

  return [
    "<div style=\"font-family:sans-serif;max-width:500px;margin:0 auto;background:#ffffff;border-radius:12px;border:1px solid #e2e8f0;padding:24px;\">",
    "  <h2 style=\"color:" + badgeColor + ";margin-top:0;\">⚠️ Urgent Follow-up: Grace Period Day " + daysPassed + "/30</h2>",
    "  <p><strong>" + brandName + "</strong> has been in grace period for <strong>" + daysPassed + " days</strong>.</p>",
    "  <p style=\"background:#fef2f2;padding:12px;border-radius:8px;color:#991b1b;font-size:13px;\">",
    "    <strong>" + remainingDays + " days remaining</strong> before the account is permanently deactivated and suspended (requiring full ₹1,999 re-enrollment).",
    "  </p>",
    "  <p>Please contact the client immediately to collect renewal payment (₹999) or assist with their online renewal.</p>",
    "  <hr style=\"border:none;border-top:1px solid #e2e8f0;margin:16px 0;\" />",
    "  <p style=\"color:#888;font-size:12px;margin-bottom:0;\">AppNexa Technologies — Employee Automated Alert</p>",
    "</div>",
  ].join("\n");
}

function ownerReminderHtml(brandName: string, daysDiff: number, paymentLinkUrl: string): string {
  const colour = daysDiff <= 7 ? "#f87171" : "#1b3a8c";
  const daysLabel = daysDiff === 1 ? "1 day" : `${daysDiff} days`;
  return [
    "<div style=\"background-color:#f8fafc;padding:30px 15px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1e293b;line-height:1.6;\">",
    "  <div style=\"max-width:540px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.06);border:1px solid #e2e8f0;\">",
    "    <div style=\"background:linear-gradient(135deg, #1b3a8c, #2f6bff);padding:24px 28px;text-align:center;\">",
    "      <h1 style=\"color:#ffffff;margin:0;font-size:22px;font-weight:800;letter-spacing:-0.5px;\">AppNexa Technologies</h1>",
    "      <p style=\"color:#cbd5e1;margin:4px 0 0;font-size:13px;font-weight:500;\">Subscription Renewal Notice</p>",
    "    </div>",
    "    <div style=\"padding:28px;\">",
    `      <h2 style="color:${colour};margin-top:0;font-size:18px;">Subscription Expires in ${daysLabel}</h2>`,
    `      <p style="font-size:15px;">Dear <strong>${brandName}</strong> Owner,</p>`,
    `      <p style="font-size:14px;color:#334155;">Your review page and counter standee subscription is due for renewal in <strong>${daysLabel}</strong>. Pay <strong>₹999</strong> to keep your review page active and continue boosting 5-star customer reviews.</p>`,
    "      <div style=\"text-align:center;margin:28px 0 20px;\">",
    `        <a href="${paymentLinkUrl}" style="background:linear-gradient(135deg, #10b981, #059669);color:#ffffff;text-decoration:none;padding:14px 32px;font-size:15px;font-weight:bold;border-radius:10px;display:inline-block;box-shadow:0 4px 14px rgba(16,185,129,0.35);">`,
    "          💳 Pay ₹999 &amp; Renew Subscription &rarr;",
    "        </a>",
    "        <div style=\"font-size:12px;color:#64748b;margin-top:8px;\">Instant Activation &bull; UPI (GPay, PhonePe, Paytm) / Cards / NetBanking</div>",
    "      </div>",
    "      <hr style=\"border:none;border-top:1px solid #e2e8f0;margin:24px 0;\" />",
    "      <div style=\"font-size:12px;color:#64748b;line-height:1.6;\">",
    "        Need help or prefer paying via bank transfer? Call/WhatsApp: <a href=\"tel:+918866390389\" style=\"color:#1b3a8c;font-weight:bold;text-decoration:none;\">+91 8866390389</a>.",
    "      </div>",
    "    </div>",
    "    <div style=\"background:#f1f5f9;padding:14px 28px;text-align:center;font-size:11px;color:#94a3b8;border-top:1px solid #e2e8f0;\">",
    "      AppNexa Technologies &bull; Surat, Gujarat &bull; Automated Renewal Notice",
    "    </div>",
    "  </div>",
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
    "  AppNexa Technologies — automated employee notice",
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
    "  AppNexa Technologies — weekly admin digest",
    "</p>",
    "</div>",
  ].join("\n");
}

// ---------------------------------------------------------------------------
// sendRenewalReminders — daily scheduled
// ---------------------------------------------------------------------------

/**
 * Daily scheduled function.
 * 1. At the 30 / 15 / 7 / 1-day windows before each business's renewal_date:
 *    - Sends upcoming renewal reminder to owner with direct Razorpay payment link.
 * 2. At 1 / 7 / 15 / 30-day windows after expiry while in GRACE PERIOD:
 *    - Sends professional grace period reminder with direct Razorpay activation link & penalty warning.
 *
 * Writes one notifications/{id} doc per email sent.
 * Idempotent: skips if already notified within the last 20 hours.
 */
export const sendRenewalReminders = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Asia/Kolkata",
    secrets: [brevoApiKey, razorpayKeyId, razorpayKeySecret],
    maxInstances: 1,
    region: "asia-south1",
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const PRE_WINDOWS = [30, 15, 7, 1];
    const GRACE_WINDOWS = [1, 7, 15, 30];
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

      const renewalDate = renewalTs.toDate();
      const brandName = biz.brand_name || bizDoc.id;
      const subStatus = biz.subscription_status ?? "active";
      const daysDiff = Math.round(
        (renewalDate.getTime() - now.getTime()) / MS_PER_DAY
      );

      let notifType = "";
      let subject = "";
      let ownerHtml = "";
      let plainText = "";
      let empSubject = "";
      let empHtml = "";
      let empText = "";

      const isPreExpiry = subStatus === "active" && daysDiff > 0 && PRE_WINDOWS.includes(daysDiff);
      const daysPassed = Math.abs(daysDiff);
      const isGrace = (subStatus === "grace_period" || (daysDiff <= 0 && biz.has_grace_branches)) && GRACE_WINDOWS.includes(daysPassed);

      if (!isPreExpiry && !isGrace) continue;

      // ── Create or retrieve Razorpay Payment Link for Renewal ──────────────
      let paymentLinkUrl = `https://${reviewDomain.value() || "appnexa.co.in"}/app/#/renew/${bizDoc.id}`;
      try {
        const razorpay = new Razorpay({
          key_id: razorpayKeyId.value(),
          key_secret: razorpayKeySecret.value(),
        });
        const plink = await (razorpay as unknown as {
          paymentLink: {
            create: (opts: Record<string, unknown>) => Promise<{id: string; short_url: string}>;
          };
        }).paymentLink.create({
          amount: 99900,
          currency: "INR",
          description: `Annual Renewal (₹999) — ${brandName}`,
          notes: {
            businessId: bizDoc.id,
            type: "annual_renewal",
          },
          notify: {sms: false, email: false},
          callback_url: `https://${reviewDomain.value() || "appnexa.co.in"}/app/#/owner`,
          callback_method: "get",
        });
        if (plink?.short_url) {
          paymentLinkUrl = plink.short_url;
        }
      } catch (plinkErr) {
        logger.warn("sendRenewalReminders: payment link creation failed, falling back", {
          err: plinkErr,
          businessId: bizDoc.id,
        });
      }

      if (isPreExpiry) {
        // ── Case A: Pre-Expiry Reminders (30, 15, 7, 1 days before expiry) ──
        notifType = `renewal_reminder_${daysDiff}`;
        const daysLabel = daysDiff === 1 ? "1 day" : `${daysDiff} days`;
        subject = daysDiff === 1 ?
          `⚠️ Review page expires tomorrow — ${brandName}` :
          `Renewal in ${daysLabel} — ${brandName}`;
        plainText =
          `Your review page subscription expires in ${daysLabel}. ` +
          `Pay ₹999 to keep your review page active: ${paymentLinkUrl}`;
        ownerHtml = ownerReminderHtml(brandName, daysDiff, paymentLinkUrl);

        empSubject = `Follow-up: ${brandName} renewal in ${daysLabel}`;
        empHtml = employeeReminderHtml(brandName, daysDiff);
        empText = `${brandName} subscription expires in ${daysLabel}. Payment link: ${paymentLinkUrl}`;
      } else if (isGrace) {
        // ── Case B: Grace Period Reminders (Day 1, 7, 15, 30 of Grace Period) ──
        notifType = `grace_period_reminder_${daysPassed}`;
        const remainingDays = Math.max(0, 30 - daysPassed);
        const renewalDateStr = renewalDate.toLocaleDateString("en-IN", {
          day: "numeric",
          month: "short",
          year: "numeric",
        });

        subject = daysPassed === 30 || remainingDays <= 1 ?
          `🚨 FINAL DAY: Grace period expiring — ${brandName} will be deactivated` :
          `⚠️ Grace Period Day ${daysPassed}/30: Renew ${brandName} to avoid ₹1,999 penalty`;

        plainText =
          `Your subscription is on Day ${daysPassed} of its 30-Day Grace Period (${remainingDays} days left). ` +
          `Pay ₹999 to reactivate your business immediately: ${paymentLinkUrl}. If not renewed, re-enrollment will cost ₹1,999.`;

        ownerHtml = ownerGracePeriodReminderHtml(
          brandName,
          daysPassed,
          remainingDays,
          renewalDateStr,
          paymentLinkUrl
        );

        empSubject = `URGENT: ${brandName} in Grace Period (Day ${daysPassed}/30 - ${remainingDays} days left)`;
        empHtml = employeeGracePeriodReminderHtml(
          brandName,
          daysPassed,
          remainingDays
        );
        empText =
          `URGENT: ${brandName} is on Day ${daysPassed} of Grace Period (${remainingDays} days left). ` +
          `Client payment link: ${paymentLinkUrl}.`;
      }

      // ── Idempotency ───────────────────────────────────────────────
      const alreadySent = await isAlreadyNotified(bizDoc.id, notifType);
      if (alreadySent) {
        logger.info("sendRenewalReminders: already notified", {
          businessId: bizDoc.id, notifType,
        });
        continue;
      }

      // ── Owner notification ────────────────────────────────────────
      const ownerEmail = biz.owner_email;
      if (ownerEmail) {
        await sendNotification({
          to: {
            email: ownerEmail,
            name: brandName,
            role: "owner",
            fcmToken: biz.owner_fcm_token ?? null,
          },
          subject,
          html: ownerHtml,
          text: plainText,
          type: notifType,
          businessId: bizDoc.id,
        });
      } else {
        logger.warn("sendRenewalReminders: no owner_email — skipping owner", {
          businessId: bizDoc.id,
        });
      }

      // ── Employee notification (sent to enroller if active) ─────────
      const empId = biz.enrolled_by;
      if (!empId || empId === "admin") continue;

      try {
        const empSnap = await db.collection("employees").doc(empId).get();
        if (!empSnap.exists || empSnap.data()?.status === "inactive" || empSnap.data()?.active === false) {
          // Employee is deactivated / offboarded: admin handles business renewals directly
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
          subject: empSubject,
          html: empHtml,
          text: empText,
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
// sendOwnerWelcomeEmail — exported helper (Owner Activation & Password Setup)
// ---------------------------------------------------------------------------

export interface SendOwnerWelcomeEmailOpts {
  ownerEmail: string;
  ownerName: string;
  brandName: string;
  setupPasswordLink: string;
  businessId: string;
  businessCode?: string;
  amount?: number;
  paymentMode?: "online" | "cash";
  paymentReference?: string;
  branches?: Array<{name: string; address?: string; amount?: number}>;
}

/**
 * Sends a welcome & account activation email to the business owner with
 * their magic password setup link, PDF invoice/receipt attachment, and dashboard details.
 *
 * @param {SendOwnerWelcomeEmailOpts} opts - Welcome email options.
 * @return {Promise<void>}
 */
export async function sendOwnerWelcomeEmail(
  opts: SendOwnerWelcomeEmailOpts
): Promise<void> {
  const {ownerEmail, ownerName, brandName, setupPasswordLink, businessId, businessCode} = opts;
  const amount = opts.amount || 1999;
  const paymentMode = opts.paymentMode || "online";
  const branches = opts.branches || [];
  const branchCount = branches.length;

  const now = new Date();
  const dateStr = now.toLocaleDateString("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
  const invoiceNumber = `INV-${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}-${businessCode ? businessCode.replace(/[^A-Za-z0-9]/g, "") : businessId.slice(-4).toUpperCase()}`;

  let pdfBase64: string | undefined;
  try {
    const pdfBuffer = await generateInvoicePdf({
      invoiceNumber,
      businessCode,
      dateStr,
      ownerName,
      brandName,
      ownerEmail,
      amount,
      paymentMode,
      paymentReference: opts.paymentReference,
      branches: branches.length > 0 ? branches : undefined,
    });
    pdfBase64 = pdfBuffer.toString("base64");
  } catch (pdfErr) {
    logger.error("sendOwnerWelcomeEmail: PDF invoice generation failed", {pdfErr, businessId});
  }

  const attachments = pdfBase64 ?
    [
      {
        name: `AppNexa_Invoice_${invoiceNumber}.pdf`,
        content: pdfBase64,
      },
    ] :
    undefined;

  const subject = branchCount > 1 ?
    `🎉 Welcome to AppNexa! Your ${branchCount} Smart Standees are Activated — ${brandName}` :
    `🎉 Welcome to AppNexa! Your Smart Standee is Activated — ${brandName}`;

  const branchListText = branchCount > 0 ?
    `\nActivated Locations (${branchCount}):\n` +
    branches.map((b) => ` • ${b.name} (₹${(b.amount || Math.round(amount / branchCount)).toLocaleString("en-IN")})`).join("\n") + "\n" :
    "";

  const plainText =
    `Hello ${ownerName},\n\n` +
    `Congratulations! Your business "${brandName}" is now active on AppNexa.\n` +
    (businessCode ? `Client ID: ${businessCode}\n` : "") +
    "Your automated review collection system is live, and your custom Smart Standees are in production.\n\n" +
    branchListText +
    `Payment Receipt: ₹${amount.toLocaleString("en-IN")} (${paymentMode === "cash" ? "Cash Collection" : "Online Razorpay"})\n` +
    `Invoice No: ${invoiceNumber}\n` +
    "Tax Status: GST Exemption (Turnover under limit as per Sec 22 of CGST Act)\n\n" +
    "Set up your Owner password & access your live dashboard here:\n" +
    `${setupPasswordLink}\n\n` +
    `Owner Portal: https://appnexa.co.in/app (Login with: ${ownerEmail})\n\n` +
    "Need help? Contact support on WhatsApp: +91 8866390389 or email support@appnexa.co.in\n\n" +
    "AppNexa Technologies";

  const branchReceiptRowsHtml = branches.length > 0 ?
    [
      "                  <tr>",
      `                    <td colspan="2" style="padding: 10px 0 4px 0; font-weight: 700; color: #1E293B; border-top: 1px solid #E2E8F0;">Activated Locations (${branchCount}):</td>`,
      "                  </tr>",
      ...branches.map((b) => {
        const bAmt = (b.amount || Math.round(amount / branchCount)).toLocaleString("en-IN");
        return `                  <tr><td style="padding: 2px 0 2px 12px; color: #475569;">• ${b.name}</td><td align="right" style="padding: 2px 0; color: #475569;">₹${bAmt}</td></tr>`;
      }),
    ].join("\n") :
    "";

  const html = [
    "<!DOCTYPE html>",
    "<html>",
    "<head>",
    "  <meta charset=\"utf-8\">",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
    `  <title>${subject}</title>`,
    "</head>",
    "<body style=\"margin: 0; padding: 0; background-color: #F8FAFC; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1E293B;\">",
    "  <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"table-layout: fixed;\">",
    "    <tr>",
    "      <td align=\"center\" style=\"padding: 32px 16px;\">",
    "        <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"max-width: 580px; background-color: #FFFFFF; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.06); border: 1px solid #E2E8F0;\">",
    "          <!-- Gradient Header -->",
    "          <tr>",
    "            <td style=\"background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%); padding: 36px 32px; text-align: center;\">",
    "              <h1 style=\"margin: 0; color: #FFFFFF; font-size: 26px; font-weight: 800; letter-spacing: -0.5px;\">AppNexa</h1>",
    "              <p style=\"margin: 8px 0 0 0; color: #E0E7FF; font-size: 14px; font-weight: 500;\">Smart NFC & QR Review Management</p>",
    "            </td>",
    "          </tr>",
    "          <!-- Main Content -->",
    "          <tr>",
    "            <td style=\"padding: 36px 32px 28px 32px;\">",
    "              <div style=\"background-color: #F0FDF4; border: 1px solid #BBF7D0; border-radius: 10px; padding: 12px 16px; margin-bottom: 24px; text-align: center;\">",
    "                <span style=\"font-size: 16px;\">🚀</span>",
    "                <strong style=\"color: #15803D; font-size: 14px; margin-left: 6px;\">Business Activated & Payment Confirmed!</strong>",
    "              </div>",
    `              <h2 style="margin: 0 0 16px 0; color: #0F172A; font-size: 20px; font-weight: 700;">Hello ${ownerName},</h2>`,
    "              <p style=\"margin: 0 0 16px 0; font-size: 15px; line-height: 1.6; color: #334155;\">",
    `                Congratulations! Your business <strong>${brandName}</strong> is now officially active on <strong>AppNexa</strong>.`,
    "              </p>",
    "              <p style=\"margin: 0 0 24px 0; font-size: 15px; line-height: 1.6; color: #334155;\">",
    branchCount > 1 ?
      `                Your automated Google Review system is live for all <strong>${branchCount} locations</strong>, and your custom acrylic Smart Standees with NFC + QR code are moving to physical production.` :
      "                Your automated Google Review system is live, and your custom acrylic Smart Standee with NFC + QR code is moving to physical production.",
    "              </p>",
    "              <!-- Account Details Box -->",
    "              <div style=\"background-color: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 12px; padding: 20px; margin-bottom: 24px;\">",
    "                <div style=\"font-size: 12px; text-transform: uppercase; font-weight: 700; color: #64748B; letter-spacing: 0.5px; margin-bottom: 12px;\">Your Account Credentials</div>",
    (businessCode ? [
      "                <div style=\"margin-bottom: 8px; font-size: 14px; color: #1E293B;\">",
      `                  <strong style="color: #475569;">Client ID:</strong> <span style="font-weight: 700; color: #1B3A8C;">${businessCode}</span>`,
      "                </div>",
    ].join("\n") : ""),
    "                <div style=\"margin-bottom: 8px; font-size: 14px; color: #1E293B;\">",
    `                  <strong style="color: #475569;">Registered Email:</strong> ${ownerEmail}`,
    "                </div>",
    "                <div style=\"margin-bottom: 8px; font-size: 14px; color: #1E293B;\">",
    `                  <strong style="color: #475569;">Business Name:</strong> ${brandName}`,
    "                </div>",
    "                <div style=\"font-size: 14px; color: #1E293B;\">",
    "                  <strong style=\"color: #475569;\">Web Portal:</strong> <a href=\"https://appnexa.co.in/app\" style=\"color: #4F46E5; text-decoration: none; font-weight: 600;\">appnexa.co.in/app</a>",
    "                </div>",
    "              </div>",
    "              <!-- CTA Button -->",
    "              <div style=\"text-align: center; margin: 28px 0;\">",
    `                <a href="${setupPasswordLink}" style="display: inline-block; background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%); color: #FFFFFF; padding: 15px 36px; border-radius: 10px; font-size: 15px; font-weight: 700; text-decoration: none; box-shadow: 0 4px 14px rgba(79, 70, 229, 0.35);">`,
    "                  Set Up Your Password & Log In →",
    "                </a>",
    "              </div>",
    "              <p style=\"text-align: center; margin: 0 0 24px 0; font-size: 12px; color: #64748B;\">",
    "                Button not clickable? Copy and paste this link into your browser:<br/>",
    `                <a href="${setupPasswordLink}" style="color: #4F46E5; word-break: break-all; font-size: 11px;">${setupPasswordLink}</a>`,
    "              </p>",
    "              <!-- Payment Receipt & Invoice Box -->",
    "              <div style=\"background-color: #F1F5F9; border: 1px solid #CBD5E1; border-radius: 12px; padding: 20px; margin-bottom: 28px;\">",
    "                <div style=\"margin-bottom: 12px;\">",
    "                  <span style=\"font-size: 12px; text-transform: uppercase; font-weight: 700; color: #475569; letter-spacing: 0.5px;\">📄 Payment Receipt & Tax Invoice</span>",
    "                </div>",
    "                <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"font-size: 13px; color: #334155; line-height: 1.6;\">",
    "                  <tr>",
    "                    <td style=\"padding: 4px 0;\"><strong>Invoice No:</strong></td>",
    `                    <td align="right" style="padding: 4px 0;">${invoiceNumber}</td>`,
    "                  </tr>",
    "                  <tr>",
    "                    <td style=\"padding: 4px 0;\"><strong>Date:</strong></td>",
    `                    <td align="right" style="padding: 4px 0;">${dateStr}</td>`,
    "                  </tr>",
    "                  <tr>",
    "                    <td style=\"padding: 4px 0;\"><strong>Plan:</strong></td>",
    `                    <td align="right" style="padding: 4px 0;">AppNexa Pro + Smart Standee (${branchCount > 1 ? `${branchCount} Locations` : "1-Year"})</td>`,
    "                  </tr>",
    "                  <tr>",
    "                    <td style=\"padding: 4px 0;\"><strong>Payment Mode:</strong></td>",
    `                    <td align="right" style="padding: 4px 0;">${paymentMode === "cash" ? "Cash Collection" : "Online (Razorpay)"}</td>`,
    "                  </tr>",
    branchReceiptRowsHtml,
    "                  <tr>",
    "                    <td style=\"padding: 8px 0 4px 0; border-top: 1px dashed #CBD5E1;\"><strong>Total Paid:</strong></td>",
    `                    <td align="right" style="padding: 8px 0 4px 0; border-top: 1px dashed #CBD5E1; font-weight: 700; color: #059669; font-size: 15px;">₹${amount.toLocaleString("en-IN")} (PAID)</td>`,
    "                  </tr>",
    "                </table>",
    "                <div style=\"margin-top: 12px; background-color: #FEF3C7; border: 1px solid #FDE68A; border-radius: 8px; padding: 10px; font-size: 11px; color: #92400E; line-height: 1.4;\">",
    "                  <strong>Tax Note:</strong> Billed under GST Turnover Exemption limit as per Section 22 of CGST Act, 2017 (No GST collected). Your official PDF invoice is attached to this email.",
    "                </div>",
    "              </div>",
    "              <hr style=\"border: none; border-top: 1px solid #E2E8F0; margin: 28px 0;\" />",
    "              <!-- Features highlight -->",
    "              <h3 style=\"margin: 0 0 14px 0; font-size: 15px; color: #0F172A; font-weight: 700;\">What you can do in your Owner Portal:</h3>",
    "              <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"font-size: 14px; line-height: 1.6; color: #334155;\">",
    "                <tr>",
    "                  <td style=\"padding: 6px 0; vertical-align: top; width: 24px;\">📊</td>",
    "                  <td style=\"padding: 6px 0;\"><strong>Live Customer Scan Tracker:</strong> See every customer scan and rating in real time.</td>",
    "                </tr>",
    "                <tr>",
    "                  <td style=\"padding: 6px 0; vertical-align: top; width: 24px;\">⭐</td>",
    "                  <td style=\"padding: 6px 0;\"><strong>Negative Feedback Shield:</strong> Capture customer concerns on WhatsApp privately before they post public negative reviews.</td>",
    "                </tr>",
    "                <tr>",
    "                  <td style=\"padding: 6px 0; vertical-align: top; width: 24px;\">📱</td>",
    "                  <td style=\"padding: 6px 0;\"><strong>Digital QR & Standee Status:</strong> Download instant digital review QRs and track standee shipping.</td>",
    "                </tr>",
    "              </table>",
    "            </td>",
    "          </tr>",
    "          <!-- Footer -->",
    "          <tr>",
    "            <td style=\"background-color: #F8FAFC; border-top: 1px solid #E2E8F0; padding: 24px 32px; text-align: center;\">",
    "              <p style=\"margin: 0 0 6px 0; font-size: 13px; font-weight: 600; color: #475569;\">AppNexa Technologies</p>",
    "              <p style=\"margin: 0 0 12px 0; font-size: 12px; color: #94A3B8;\">Smart NFC & QR Review Management System</p>",
    "              <p style=\"margin: 0; font-size: 12px; color: #64748B;\">",
    "                WhatsApp: <a href=\"https://wa.me/918866390389\" style=\"color: #4F46E5; text-decoration: none;\">+91 8866390389</a> · ",
    "                Email: <a href=\"mailto:support@appnexa.co.in\" style=\"color: #4F46E5; text-decoration: none;\">support@appnexa.co.in</a> · ",
    "                Web: <a href=\"https://appnexa.co.in\" style=\"color: #4F46E5; text-decoration: none;\">appnexa.co.in</a>",
    "              </p>",
    "            </td>",
    "          </tr>",
    "        </table>",
    "      </td>",
    "    </tr>",
    "  </table>",
    "</body>",
    "</html>",
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
    type: "owner_welcome",
    businessId,
    attachments,
  });
}

// ---------------------------------------------------------------------------
// sendPaymentLinkEmail — exported helper (Change 3)
// ---------------------------------------------------------------------------

/**
 * Sends a payment link to the business owner by email and writes a Firestore
 * notification document.
 *
 * @param {SendPaymentLinkEmailOpts} opts - Payment link email options.
 * @return {Promise<void>}
 */
export async function sendPaymentLinkEmail(
  opts: SendPaymentLinkEmailOpts
): Promise<void> {
  const {ownerEmail, ownerName, brandName, paymentLinkUrl, businessId} = opts;
  const amount = opts.amount || 1999;
  const branchNames = opts.branchNames || opts.branches?.map((b) => b.name) || [];
  const branchCount = branchNames.length;

  const subject = branchCount > 1 ?
    `Complete your enrollment payment (${branchCount} Locations) — ${brandName}` :
    (branchCount === 1 ?
      `Complete your enrollment payment (${branchNames[0]}) — ${brandName}` :
      `Complete your enrollment payment — ${brandName}`);

  const branchListText = branchCount > 0 ?
    `\nEnrolled Locations (${branchCount}):\n` +
    branchNames.map((b) => ` • ${b}`).join("\n") + "\n" :
    "";

  const plainText =
    `Hello ${ownerName},\n\n` +
    `Your enrollment for ${brandName} is pending payment.\n` +
    branchListText +
    `Please pay the ₹${amount.toLocaleString("en-IN")} setup fee to activate your review pages and Smart Standees:\n` +
    `${paymentLinkUrl}\n\n` +
    "⏳ Please note: This payment link is valid for 47 hours.\n\n" +
    "AppNexa Support";

  const branchRowsHtml = branchCount > 0 ?
    [
      "                  <tr>",
      `                    <td colspan="2" style="padding: 8px 0 4px 0; font-weight: 700; color: #1E293B; border-top: 1px solid #E2E8F0;">Enrolled Locations (${branchCount}):</td>`,
      "                  </tr>",
      ...branchNames.map((b) => `                  <tr><td colspan="2" style="padding: 2px 0 2px 8px; color: #475569;">• ${b}</td></tr>`),
    ].join("\n") :
    "";

  const html = [
    "<!DOCTYPE html>",
    "<html>",
    "<head>",
    "  <meta charset=\"utf-8\">",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
    `  <title>${subject}</title>`,
    "</head>",
    "<body style=\"margin: 0; padding: 0; background-color: #F8FAFC; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1E293B;\">",
    "  <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"table-layout: fixed;\">",
    "    <tr>",
    "      <td align=\"center\" style=\"padding: 32px 16px;\">",
    "        <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"max-width: 580px; background-color: #FFFFFF; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.06); border: 1px solid #E2E8F0;\">",
    "          <!-- Gradient Header -->",
    "          <tr>",
    "            <td style=\"background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%); padding: 32px; text-align: center;\">",
    "              <h1 style=\"margin: 0; color: #FFFFFF; font-size: 24px; font-weight: 800;\">AppNexa</h1>",
    "              <p style=\"margin: 6px 0 0 0; color: #E0E7FF; font-size: 13px;\">Complete Your Business Enrollment</p>",
    "            </td>",
    "          </tr>",
    "          <!-- Main Content -->",
    "          <tr>",
    "            <td style=\"padding: 32px;\">",
    `              <h2 style="margin: 0 0 14px 0; color: #0F172A; font-size: 18px; font-weight: 700;">Hello ${ownerName},</h2>`,
    "              <p style=\"margin: 0 0 16px 0; font-size: 14px; line-height: 1.6; color: #334155;\">",
    branchCount > 1 ?
      `                Your enrollment for <strong>${brandName}</strong> (${branchCount} locations) is ready. To activate your automated review collection pages and initiate your custom NFC Smart Standee printing, please complete the secure online payment.` :
      `                Your enrollment for <strong>${brandName}</strong> is ready. To activate your automated review collection page and initiate your custom NFC Smart Standee printing, please complete the secure online payment.`,
    "              </p>",
    "              <div style=\"background-color: #F1F5F9; border-radius: 12px; padding: 18px; margin-bottom: 24px;\">",
    "                <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"font-size: 14px; color: #334155;\">",
    "                  <tr>",
    "                    <td><strong>Plan:</strong></td>",
    `                    <td align="right">1-Year AppNexa Pro + Smart Standee (${branchCount > 1 ? `${branchCount} Locations` : "1 Location"})</td>`,
    "                  </tr>",
    branchRowsHtml,
    "                  <tr>",
    "                    <td style=\"padding-top: 8px;\"><strong>Total Setup Fee:</strong></td>",
    `                    <td align="right" style="padding-top: 8px; font-weight: 700; color: #059669; font-size: 16px;">₹${amount.toLocaleString("en-IN")}</td>`,
    "                  </tr>",
    "                  <tr>",
    "                    <td style=\"padding-top: 8px; font-size: 12px; color: #B45309;\"><strong>Link Validity:</strong></td>",
    "                    <td align=\"right\" style=\"padding-top: 8px; font-size: 12px; font-weight: 600; color: #B45309;\">⏳ Valid for 47 hours</td>",
    "                  </tr>",
    "                </table>",
    "              </div>",
    "              <!-- CTA Button -->",
    "              <div style=\"text-align: center; margin: 28px 0;\">",
    `                <a href="${paymentLinkUrl}" style="display: inline-block; background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%); color: #FFFFFF; padding: 14px 32px; border-radius: 10px; font-size: 15px; font-weight: 700; text-decoration: none; box-shadow: 0 4px 12px rgba(79, 70, 229, 0.3);">`,
    `                  Complete Payment (₹${amount.toLocaleString("en-IN")}) →`,
    "                </a>",
    "              </div>",
    "              <p style=\"text-align: center; margin: 0; font-size: 12px; color: #64748B;\">",
    `                Direct link: <a href="${paymentLinkUrl}" style="color: #4F46E5; word-break: break-all;">${paymentLinkUrl}</a>`,
    "              </p>",
    "            </td>",
    "          </tr>",
    "          <!-- Footer -->",
    "          <tr>",
    "            <td style=\"background-color: #F8FAFC; border-top: 1px solid #E2E8F0; padding: 20px; text-align: center; font-size: 12px; color: #64748B;\">",
    "              <p style=\"margin: 0;\">AppNexa Technologies · Smart Review Management System</p>",
    "            </td>",
    "          </tr>",
    "        </table>",
    "      </td>",
    "    </tr>",
    "  </table>",
    "</body>",
    "</html>",
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

// ---------------------------------------------------------------------------
// Password Reset Email Template (Universal AppNexa Theme)
// ---------------------------------------------------------------------------

function getPasswordResetEmailHtml(email: string, resetLink: string): string {
  return [
    "<!DOCTYPE html>",
    "<html>",
    "<head>",
    "  <meta charset=\"utf-8\">",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
    "  <title>Reset Your AppNexa Password</title>",
    "</head>",
    "<body style=\"margin: 0; padding: 0; background-color: #F8FAFC; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1E293B;\">",
    "  <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"table-layout: fixed;\">",
    "    <tr>",
    "      <td align=\"center\" style=\"padding: 36px 16px;\">",
    "        <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" width=\"100%\" style=\"max-width: 560px; background-color: #FFFFFF; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 24px rgba(0,0,0,0.06); border: 1px solid #E2E8F0;\">",
    "          <!-- Brand Header -->",
    "          <tr>",
    "            <td style=\"background: linear-gradient(135deg, #1B3A8C 0%, #2F6BFF 100%); padding: 32px; text-align: center;\">",
    "              <h1 style=\"margin: 0; color: #FFFFFF; font-size: 24px; font-weight: 800; letter-spacing: -0.5px;\">AppNexa Technologies</h1>",
    "              <p style=\"margin: 6px 0 0 0; color: #E0E7FF; font-size: 13px; font-weight: 500;\">Google Review Growth &amp; Counter Standee System</p>",
    "            </td>",
    "          </tr>",
    "          <!-- Alert Header Banner -->",
    "          <tr>",
    "            <td style=\"background: #EEF2FF; border-bottom: 1px solid #E0E7FF; padding: 14px 28px; text-align: center;\">",
    "              <span style=\"font-size: 16px;\">🔒</span>",
    "              <strong style=\"color: #1E40AF; font-size: 14px; margin-left: 6px;\">Password Reset Request</strong>",
    "            </td>",
    "          </tr>",
    "          <!-- Main Body -->",
    "          <tr>",
    "            <td style=\"padding: 32px 28px 28px 28px;\">",
    "              <h2 style=\"margin: 0 0 14px 0; color: #0F172A; font-size: 18px; font-weight: 700;\">Hello,</h2>",
    "              <p style=\"margin: 0 0 16px 0; font-size: 14px; line-height: 1.6; color: #334155;\">",
    "                We received a request to reset the password for your AppNexa account registered under <strong>" + email + "</strong>.",
    "              </p>",
    "              <p style=\"margin: 0 0 24px 0; font-size: 14px; line-height: 1.6; color: #334155;\">",
    "                Click the button below to securely set a new password for your account:",
    "              </p>",
    "              <!-- Reset CTA Button -->",
    "              <div style=\"text-align: center; margin: 30px 0 24px;\">",
    "                <a href=\"" + resetLink + "\" style=\"display: inline-block; background: linear-gradient(135deg, #1B3A8C 0%, #2F6BFF 100%); color: #FFFFFF; padding: 15px 36px; border-radius: 10px; font-size: 15px; font-weight: 800; text-decoration: none; box-shadow: 0 4px 14px rgba(27,58,140,0.35); letter-spacing: 0.3px;\">",
    "                  🔐 Reset My Password &rarr;",
    "                </a>",
    "              </div>",
    "              <!-- Direct Link Fallback -->",
    "              <div style=\"background-color: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 10px; padding: 14px; margin-bottom: 24px; font-size: 12px; color: #64748B;\">",
    "                <div style=\"margin-bottom: 4px; font-weight: 600; color: #475569;\">If the button above does not work, copy and paste this link into your browser:</div>",
    "                <a href=\"" + resetLink + "\" style=\"color: #2F6BFF; word-break: break-all; text-decoration: none;\">" + resetLink + "</a>",
    "              </div>",
    "              <!-- Security Advisory Notice -->",
    "              <div style=\"background-color: #FFFBEB; border-left: 4px solid #F59E0B; padding: 14px 16px; border-radius: 0 8px 8px 0; margin-bottom: 24px;\">",
    "                <div style=\"font-weight: 700; color: #92400E; font-size: 13px; margin-bottom: 4px;\">⚠️ Important Security Information:</div>",
    "                <div style=\"font-size: 12px; color: #78350F; line-height: 1.6;\">",
    "                  &bull; This password reset link is valid for <strong>1 hour</strong>.<br/>",
    "                  &bull; If you did not request this change, you can safely ignore this email. Your password will remain unchanged.<br/>",
    "                  &bull; AppNexa team members will never ask you for your account password or OTP.",
    "                </div>",
    "              </div>",
    "              <hr style=\"border: none; border-top: 1px solid #E2E8F0; margin: 24px 0 20px;\" />",
    "              <!-- Support Footer -->",
    "              <div style=\"font-size: 12px; color: #64748B; line-height: 1.6;\">",
    "                <strong>Need assistance?</strong><br/>",
    "                Call or WhatsApp our support team at <a href=\"tel:+918866390389\" style=\"color: #1B3A8C; font-weight: bold; text-decoration: none;\">+91 8866390389</a> or email <a href=\"mailto:support@appnexa.co.in\" style=\"color: #1B3A8C; text-decoration: none;\">support@appnexa.co.in</a>.",
    "              </div>",
    "            </td>",
    "          </tr>",
    "          <!-- Footer Bar -->",
    "          <tr>",
    "            <td style=\"background-color: #F1F5F9; border-top: 1px solid #E2E8F0; padding: 16px 28px; text-align: center; font-size: 11px; color: #94A3B8;\">",
    "              AppNexa Technologies &bull; Surat, Gujarat &bull; Automated Account Security Notification",
    "            </td>",
    "          </tr>",
    "        </table>",
    "      </td>",
    "    </tr>",
    "  </table>",
    "</body>",
    "</html>",
  ].join("\n");
}

/**
 * Callable Function: sendCustomPasswordResetEmail
 * Generates an official Firebase password reset link and dispatches an
 * email using the AppNexa Universal Theme via Brevo Transactional Email.
 */
export const sendCustomPasswordResetEmail = onCall(
  {
    secrets: [brevoApiKey],
    region: "asia-south1",
    maxInstances: 10,
  },
  async (request) => {
    const {email} = request.data as {email?: string};
    if (!email || typeof email !== "string" || !email.includes("@")) {
      throw new HttpsError("invalid-argument", "A valid email address is required.");
    }

    const cleanEmail = email.trim().toLowerCase();
    const actionCodeSettings = {
      url: `https://${reviewDomain.value() || "appnexa.co.in"}/app/login`,
      handleCodeInApp: false,
    };

    let resetLink: string;
    try {
      const auth = getAuth();
      resetLink = await auth.generatePasswordResetLink(cleanEmail, actionCodeSettings);
    } catch (authErr: unknown) {
      const err = authErr as {code?: string; message?: string};
      logger.warn("sendCustomPasswordResetEmail: generatePasswordResetLink error", {
        cleanEmail,
        code: err?.code,
        message: err?.message,
      });

      if (err?.code === "auth/user-not-found") {
        throw new HttpsError(
          "not-found",
          "This email is not registered in our system. Please check the email or contact admin."
        );
      }
      throw new HttpsError(
        "internal",
        "Failed to generate password reset link. Please try again later."
      );
    }

    const subject = "🔐 Reset Your AppNexa Account Password";
    const html = getPasswordResetEmailHtml(cleanEmail, resetLink);
    const text = [
      "Hello,",
      "",
      `We received a request to reset the password for your AppNexa account (${cleanEmail}).`,
      "",
      "Reset your password by opening the link below:",
      resetLink,
      "",
      "This link is valid for 1 hour.",
      "If you did not request a password reset, you can safely ignore this email.",
      "",
      "AppNexa Technologies — Support Desk",
    ].join("\n");

    try {
      await sendBrevoEmail({
        to: cleanEmail,
        toName: cleanEmail.split("@")[0],
        subject,
        html,
        text,
      });
      logger.info("sendCustomPasswordResetEmail: reset email sent successfully", {
        cleanEmail,
      });
      return {success: true};
    } catch (emailErr) {
      logger.error("sendCustomPasswordResetEmail: failed to send email via Brevo", {
        cleanEmail,
        err: emailErr,
      });
      throw new HttpsError(
        "internal",
        "Failed to send password reset email. Please try again later."
      );
    }
  }
);

// ---------------------------------------------------------------------------
// sendOrphanPaymentAdminAlert
// ---------------------------------------------------------------------------

export interface SendOrphanPaymentAdminAlertOpts {
  adminEmail: string;
  paymentId: string;
  orderId: string | null;
  businessId: string;
  amountRupees: number;
  customerEmail: string | null;
  customerContact: string | null;
  notes: Record<string, unknown>;
}

/**
 * Dispatches an immediate high-priority alert to the Platform Admin when a payment
 * is captured on Razorpay for a business document that does not exist in Firestore.
 */
export async function sendOrphanPaymentAdminAlert(
  opts: SendOrphanPaymentAdminAlertOpts
): Promise<void> {
  const {
    adminEmail,
    paymentId,
    orderId,
    businessId,
    amountRupees,
    customerEmail,
    customerContact,
    notes,
  } = opts;

  const subject = `🚨 [URGENT ACTION] Orphan Payment Captured: ₹${amountRupees} for Deleted Business (${businessId})`;
  const text = [
    "URGENT ATTENTION REQUIRED: Orphan Payment Captured",
    "",
    `A customer payment of ₹${amountRupees} was successfully captured on Razorpay, but the business document ("${businessId}") no longer exists in Firestore (likely an abandoned draft that was purged).`,
    "",
    "Payment Details:",
    `• Payment ID: ${paymentId}`,
    `• Order ID: ${orderId || "N/A"}`,
    `• Amount: ₹${amountRupees}`,
    `• Customer Email: ${customerEmail || "N/A"}`,
    `• Customer Contact: ${customerContact || "N/A"}`,
    `• Notes: ${JSON.stringify(notes)}`,
    "",
    "Action Required:",
    `1. Review payment in Razorpay Dashboard: https://dashboard.razorpay.com/app/payments/${paymentId}`,
    "2. Issue a full refund to the customer OR manually recreate the business account in the Admin Panel.",
    "",
    "Never retain customer funds without active service fulfillment.",
    "",
    "AppNexa Technologies — Automated Sentinel",
  ].join("\n");

  const html = `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"></head>
    <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:#F8FAFC; padding:24px; color:#1E293B;">
      <div style="max-width:600px; margin:0 auto; background:#FFFFFF; border-radius:12px; border:1px solid #E2E8F0; overflow:hidden; box-shadow:0 4px 12px rgba(0,0,0,0.05);">
        <div style="background:#EF4444; padding:20px 24px; color:#FFFFFF;">
          <h2 style="margin:0; font-size:18px;">🚨 [URGENT ACTION] Orphan Payment Captured</h2>
          <p style="margin:4px 0 0; font-size:13px; opacity:0.9;">Business "${businessId}" does not exist in Firestore</p>
        </div>
        <div style="padding:24px;">
          <p style="margin:0 0 16px; font-size:14px; line-height:1.6;">
            A customer payment of <strong>₹${amountRupees}</strong> was captured on Razorpay, but the business document was not found in the database.
          </p>
          <div style="background:#F1F5F9; border-radius:8px; padding:16px; margin-bottom:20px; font-size:13px;">
            <p style="margin:4px 0;"><strong>Payment ID:</strong> <code>${paymentId}</code></p>
            <p style="margin:4px 0;"><strong>Order ID:</strong> <code>${orderId || "N/A"}</code></p>
            <p style="margin:4px 0;"><strong>Customer Email:</strong> ${customerEmail || "N/A"}</p>
            <p style="margin:4px 0;"><strong>Customer Phone:</strong> ${customerContact || "N/A"}</p>
            <p style="margin:4px 0;"><strong>Amount:</strong> ₹${amountRupees}</p>
          </div>
          <div style="text-align:center; margin:24px 0;">
            <a href="https://dashboard.razorpay.com/app/payments/${paymentId}" style="display:inline-block; background:#2563EB; color:#FFFFFF; padding:12px 24px; border-radius:8px; font-weight:700; text-decoration:none;">
              Open in Razorpay Dashboard →
            </a>
          </div>
          <p style="margin:0; font-size:12px; color:#64748B; line-height:1.5;">
            <strong>Required Action:</strong> Open Razorpay to issue a prompt refund to the customer, OR recreate the business document manually in the Admin Panel using the business ID.
          </p>
        </div>
      </div>
    </body>
    </html>
  `;

  await sendBrevoEmail({
    to: adminEmail,
    toName: "Platform Super Admin",
    subject,
    html,
    text,
  });
}


