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
import {
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";

import {
  brevoApiKey,
  brevoSenderEmail,
  adminEmail,
} from "./secrets.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Notification type identifiers written to notifications/{id}. */
type NotifType =
  | "renewal_reminder_30"
  | "renewal_reminder_15"
  | "renewal_reminder_7"
  | "renewal_reminder_1"
  | "admin_weekly_digest"
  | "cash_payment_verification";

interface NotifData {
  recipient: string;
  recipientName: string;
  recipientRole: "owner" | "employee" | "admin";
  type: NotifType;
  businessId: string | null;
  message: string;
  subject: string;
}

interface BrevoPayload {
  to: string;
  toName: string;
  subject: string;
  html: string;
  text: string;
}

// ---------------------------------------------------------------------------
// Internal: Brevo email sender
// ---------------------------------------------------------------------------

/**
 * Sends one transactional email via Brevo API v3.
 * Throws on HTTP non-2xx or missing config.
 * @param {object} opts - Email options.
 * @return {Promise<void>}
 */
async function sendBrevoEmail(opts: BrevoPayload): Promise<void> {
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
    throw new Error(
      `Brevo API ${res.status}: ${errText.slice(0, 200)}`
    );
  }
}

// ---------------------------------------------------------------------------
// Internal: Firestore notification writer
// ---------------------------------------------------------------------------

/**
 * Writes one document to notifications/{auto-id}.
 * The doc is immediately readable by the dashboard banner (doc 02).
 * @param {object} data - Notification fields.
 * @return {Promise<void>}
 */
async function writeNotification(data: NotifData): Promise<void> {
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

/**
 * Builds the HTML body for a renewal reminder sent to the business owner.
 * @param {string} brandName - Business display name.
 * @param {number} daysDiff - Days until renewal.
 * @return {string} HTML string.
 */
function ownerReminderHtml(
  brandName: string,
  daysDiff: number
): string {
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
    "Pay <strong>\u20b9999</strong> to keep your review page ",
    "active and continue collecting customer reviews.</p>",
    "<p>Log in to your dashboard to renew now.</p>",
    "<hr/>",
    "<p style=\"color:#888;font-size:12px;\">",
    "  Review System \u2014 automated renewal notice",
    "</p>",
    "</div>",
  ].join("\n");
}

/**
 * Builds the HTML body for a renewal reminder sent to the employee.
 * @param {string} brandName - Business display name.
 * @param {number} daysDiff - Days until renewal.
 * @return {string} HTML string.
 */
function employeeReminderHtml(
  brandName: string,
  daysDiff: number
): string {
  const daysLabel = daysDiff === 1 ? "1 day" : `${daysDiff} days`;
  return [
    "<div style=\"font-family:sans-serif;",
    "max-width:480px;margin:0 auto;\">",
    "<h2>Client Renewal Reminder</h2>",
    `<p><strong>${brandName}</strong> \u2014 subscription expires `,
    `in <strong>${daysLabel}</strong>.</p>`,
    "<p>Please follow up with the business owner to ensure they ",
    "renew before the subscription lapses.</p>",
    "<hr/>",
    "<p style=\"color:#888;font-size:12px;\">",
    "  Review System \u2014 automated employee notice",
    "</p>",
    "</div>",
  ].join("\n");
}

/**
 * Builds the HTML table for the weekly admin digest.
 * @param {Array} rows - Renewal data rows.
 * @return {string} HTML string.
 */
function adminDigestHtml(
  rows: Array<{
    name: string;
    renewal: string;
    days: number | string;
    status: string;
  }>
): string {
  const trs = rows.map((r) =>
    `<tr>
      <td style="padding:6px 10px;">${r.name}</td>
      <td style="padding:6px 10px;">${r.renewal}</td>
      <td style="padding:6px 10px;">${r.days} days</td>
      <td style="padding:6px 10px;">${r.status}</td>
    </tr>`
  ).join("\n");

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
    "  Review System \u2014 weekly admin digest",
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
    const WINDOWS = [30, 15, 7, 1] as const;
    const MS_PER_DAY = 24 * 60 * 60 * 1000;

    const bizSnap = await db
      .collection("businesses")
      .where(
        "subscription_status", "in", ["active", "grace_period"]
      )
      .get();

    logger.info("sendRenewalReminders: checking businesses", {
      count: bizSnap.size,
    });

    for (const bizDoc of bizSnap.docs) {
      const biz = bizDoc.data() as {
        brand_name?: string;
        owner_email?: string;
        currently_managed_by?: string;
        enrolled_by?: string;
        renewal_date?: Timestamp;
      };

      const renewalTs = biz.renewal_date;
      if (!renewalTs) continue;

      // Guard: skip documents where renewal_date was stored as a plain string
      // instead of a Firestore Timestamp (old seed data may have done this).
      if (typeof (renewalTs as unknown as {toDate?: unknown}).toDate !== "function") {
        logger.warn("sendRenewalReminders: renewal_date is not a Timestamp, skipping", {
          businessId: bizDoc.id,
          renewalDate: renewalTs,
        });
        continue;
      }

      const daysDiff = Math.round(
        (renewalTs.toDate().getTime() - now.getTime()) / MS_PER_DAY
      );

      if (!(WINDOWS as readonly number[]).includes(daysDiff)) continue;

      const notifType =
        `renewal_reminder_${daysDiff}` as NotifType;
      const brandName = biz.brand_name || bizDoc.id;

      // ── Idempotency ───────────────────────────────────────────────
      const alreadySent = await isAlreadyNotified(
        bizDoc.id, notifType
      );
      if (alreadySent) {
        logger.info("sendRenewalReminders: already notified", {
          businessId: bizDoc.id, notifType,
        });
        continue;
      }

      const daysLabel =
        daysDiff === 1 ? "1 day" : `${daysDiff} days`;

      // ── Email: business owner ─────────────────────────────────────
      const ownerEmail = biz.owner_email;
      if (ownerEmail) {
        const subject = daysDiff === 1 ?
          `\u26a0\ufe0f Review page expires tomorrow \u2014 ${brandName}` :
          `Renewal in ${daysLabel} \u2014 ${brandName}`;
        const plainText =
          `Your review page subscription expires in ${daysLabel}. ` +
          "Pay \u20b9999 to keep your review page active.";

        // Write to Firestore FIRST so the dashboard banner always
        // shows the notification even if the Brevo send fails.
        try {
          await writeNotification({
            recipient: ownerEmail,
            recipientName: brandName,
            recipientRole: "owner",
            type: notifType,
            businessId: bizDoc.id,
            message: plainText,
            subject,
          });
        } catch (wErr) {
          logger.error(
            "sendRenewalReminders: writeNotification failed (owner)",
            {businessId: bizDoc.id, wErr}
          );
        }

        // Then send the email (best-effort, non-fatal)
        try {
          await sendBrevoEmail({
            to: ownerEmail,
            toName: brandName,
            subject,
            html: ownerReminderHtml(brandName, daysDiff),
            text: plainText,
          });
          logger.info("sendRenewalReminders: owner email sent", {
            businessId: bizDoc.id, daysDiff,
          });
        } catch (err) {
          logger.error(
            "sendRenewalReminders: owner Brevo send failed",
            {businessId: bizDoc.id, err}
          );
        }
      } else {
        logger.warn(
          "sendRenewalReminders: no owner_email — skipping owner",
          {businessId: bizDoc.id}
        );
      }

      // ── Email: enrolling / managing employee ──────────────────────
      const empId =
        biz.currently_managed_by || biz.enrolled_by;
      if (!empId || empId === "admin") continue;

      try {
        const empSnap = await db
          .collection("employees")
          .doc(empId)
          .get();
        if (!empSnap.exists) continue;

        const emp = empSnap.data() as {
          name?: string;
          contact?: string;
        };
        const empEmail = emp.contact || "";
        const empName = emp.name || "Employee";

        // Only send if contact looks like an email address
        if (!empEmail.includes("@")) {
          logger.warn(
            "sendRenewalReminders: employee contact is " +
            "not an email — skipping",
            {empId}
          );
          continue;
        }

        const empSubject =
          `Follow-up: ${brandName} renewal in ${daysLabel}`;
        const empText =
          `${brandName} subscription expires in ${daysLabel}. ` +
          "Please follow up with the business owner.";

        // Write notification BEFORE sending email (best-effort)
        try {
          await writeNotification({
            recipient: empEmail,
            recipientName: empName,
            recipientRole: "employee",
            type: notifType,
            businessId: bizDoc.id,
            message: empText,
            subject: empSubject,
          });
        } catch (wErr) {
          logger.error(
            "sendRenewalReminders: writeNotification failed (emp)",
            {businessId: bizDoc.id, empId, wErr}
          );
        }

        try {
          await sendBrevoEmail({
            to: empEmail,
            toName: empName,
            subject: empSubject,
            html: employeeReminderHtml(brandName, daysDiff),
            text: empText,
          });
          logger.info("sendRenewalReminders: employee email sent", {
            businessId: bizDoc.id, empId, daysDiff,
          });
        } catch (err) {
          logger.error(
            "sendRenewalReminders: employee Brevo send failed",
            {businessId: bizDoc.id, empId, err}
          );
        }
      } catch (err) {
        logger.error(
          "sendRenewalReminders: employee block failed",
          {businessId: bizDoc.id, empId, err}
        );
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
 * Requires BREVO_API_KEY (secret), BREVO_SENDER_EMAIL and
 * ADMIN_EMAIL (params).
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
      logger.warn(
        "sendAdminDigest: ADMIN_EMAIL param not set — skipping"
      );
      return;
    }

    const db = getFirestore();
    const now = new Date();
    const MS_PER_DAY = 24 * 60 * 60 * 1000;

    // Fetch all active/grace businesses; filter by date in code
    // to avoid a composite index on renewal_date + subscription_status.
    const snap = await db
      .collection("businesses")
      .where(
        "subscription_status", "in", ["active", "grace_period"]
      )
      .get();

    const rows = snap.docs
      .map((doc) => {
        const d = doc.data();
        const renewal: Date | undefined =
          d.renewal_date?.toDate();
        const days = renewal ?
          Math.round(
            (renewal.getTime() - now.getTime()) / MS_PER_DAY
          ) :
          null;
        return {
          id: doc.id,
          name: (d.brand_name as string | undefined) || doc.id,
          renewal: renewal ?
            renewal.toLocaleDateString("en-IN") : "\u2014",
          days,
          status:
            (d.subscription_status as string | undefined) || "\u2014",
        };
      })
      .filter((r) => r.days !== null && r.days >= 0 && r.days <= 30)
      .sort((a, b) => (a.days ?? 0) - (b.days ?? 0));

    logger.info("sendAdminDigest: upcoming renewals", {
      count: rows.length,
    });

    if (rows.length === 0) {
      logger.info("sendAdminDigest: no upcoming renewals — skip");
      return;
    }

    const subject =
      `Weekly Renewal Digest \u2014 ${rows.length} upcoming`;
    const plainText = rows
      .map(
        (r) => `${r.name}: ${r.renewal} (${r.days} days) — ${r.status}`
      )
      .join("\n");

    await sendBrevoEmail({
      to: toEmail,
      toName: "Admin",
      subject,
      html: adminDigestHtml(
        rows as Array<{
          name: string;
          renewal: string;
          days: number;
          status: string;
        }>
      ),
      text: plainText,
    });

    await writeNotification({
      recipient: toEmail,
      recipientName: "Admin",
      recipientRole: "admin",
      type: "admin_weekly_digest",
      businessId: null,
      message:
        `${rows.length} business renewal(s) in the next 30 days.`,
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

    const comm = commSnap.data() as {
      business_id?: string;
      employee_id?: string;
      amount?: number;
      date_claimed?: Timestamp;
      payment_mode?: string;
    };

    if (comm.payment_mode !== "cash") {
      throw new HttpsError(
        "invalid-argument",
        "Verification email is only for cash payments."
      );
    }

    // Avoid destructuring snake_case Firestore fields
    // (ESLint camelcase rule) — access via comm.field_name.
    const bizId = comm.business_id;
    const empId = comm.employee_id;
    const amount = comm.amount;
    const dateClaimed = comm.date_claimed;

    if (!bizId) {
      throw new HttpsError(
        "internal",
        "Commission record is missing business_id."
      );
    }

    // ── Read business ─────────────────────────────────────────────
    const bizSnap = await db
      .collection("businesses")
      .doc(bizId)
      .get();
    const biz = (bizSnap.data() || {}) as {
      brand_name?: string;
      owner_email?: string;
    };
    const ownerEmail = biz.owner_email;
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
      const empSnap = await db
        .collection("employees")
        .doc(empId)
        .get();
      const en = empSnap.data()?.name;
      if (typeof en === "string" && en.trim()) empName = en.trim();
    }

    // ── Build message ─────────────────────────────────────────────
    const brandName = biz.brand_name || "your business";
    const amtStr =
      `\u20b9${(amount || 0).toLocaleString("en-IN")}`;
    const dateStr = dateClaimed ?
      dateClaimed.toDate().toLocaleDateString("en-IN") :
      "recently";

    const subject = `Payment verification required \u2014 ${brandName}`;
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
      `  Record: ${commissionRecordId} \u2014 `,
      "  Review System automated verification notice",
      "</p>",
      "</div>",
    ].join("\n");

    // ── Send + write notification ─────────────────────────────────
    await sendBrevoEmail({
      to: ownerEmail,
      toName: brandName,
      subject,
      html,
      text: plainText,
    });

    await writeNotification({
      recipient: ownerEmail,
      recipientName: brandName,
      recipientRole: "owner",
      type: "cash_payment_verification",
      businessId: bizId,
      message: plainText,
      subject,
    });

    logger.info("sendCashPaymentVerification: sent", {
      businessId: bizId,
      commissionRecordId,
    });

    return {success: true};
  }
);
