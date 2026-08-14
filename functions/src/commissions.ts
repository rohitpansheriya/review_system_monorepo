/**
 * commissions.ts — Two-step cash payment verification & payout tracking
 *
 * Implements doc 06-commission-tracking.md:
 *   - Online payments: auto-verified via Razorpay webhook.
 *   - Cash payments: two-step verification fraud gate:
 *       (A) Admin confirms cash physically received / deposited.
 *       (B) Business owner confirms payment independently via dashboard or notification.
 *       Flips to "verified" ONLY when BOTH confirmations are in.
 *   - Payout tracking: flips "verified" → "paid" with payout_reference.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

// ---------------------------------------------------------------------------
// onCashCommissionCreated — Firestore Trigger (doc 06 / doc 08)
// ---------------------------------------------------------------------------

/**
 * Triggered on creation of a commission_records document.
 * If payment_mode == "cash" and status == "pending", creates an in-app notification
 * for the owner: "Did you pay ₹[amount] in cash to [Employee Name] on [date]?"
 */
export const onCashCommissionCreated = onDocumentCreated(
  {
    document: "commission_records/{recordId}",
    region: "asia-south1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (data.payment_mode !== "cash" || data.status !== "pending") return;

    const db = getFirestore();
    const bizId = data.business_id as string | undefined;
    if (!bizId) return;

    const bizSnap = await db.collection("businesses").doc(bizId).get();
    if (!bizSnap.exists) return;

    const biz = bizSnap.data() || {};
    const ownerUid = biz.owner_auth_uid as string | undefined;
    if (!ownerUid) return;

    const amount = data.amount || 1999;
    const empId = data.employee_id || "Employee";

    // Write to notifications collection for owner dashboard prompt (doc 08)
    await db.collection("notifications").add({
      recipient: ownerUid,
      type: "cash_payment_verification",
      title: "Cash Payment Verification Prompt",
      body: `Did you pay ₹${amount} in cash to ${empId}? Please confirm in your owner dashboard.`,
      commission_record_id: snap.id,
      business_id: bizId,
      read: false,
      created_at: Timestamp.now(),
    });

    logger.info("onCashCommissionCreated: owner notification created", {
      recordId: snap.id,
      ownerUid,
      bizId,
    });
  }
);

// ---------------------------------------------------------------------------
// confirmCashPaymentOwner — onCall (doc 06)
// ---------------------------------------------------------------------------

/**
 * Allows an authenticated business owner to confirm or dispute a cash payment
 * logged by an employee.
 *
 * Input:
 *   - commissionRecordId: string (required)
 *   - confirmed: boolean (required — true: "Yes, I paid", false: "No / dispute")
 *   - disputeReason?: string (optional)
 *
 * Logic:
 *   - Verifies owner owns the business associated with this commission record.
 *   - If confirmed == true:
 *       Sets owner_confirmed = true, owner_confirmed_at = now.
 *       If admin_confirmed == true → flips status to "verified", sets date_verified = now.
 *   - If confirmed == false:
 *       Sets owner_confirmed = false, disputed = true, status = "disputed".
 *       Record is flagged for admin review and NOT auto-verified or deleted.
 */
export const confirmCashPaymentOwner = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Must be signed in to confirm payment."
      );
    }

    const {commissionRecordId, confirmed, disputeReason} = (request.data || {}) as {
      commissionRecordId?: string;
      confirmed?: boolean;
      disputeReason?: string;
    };

    if (!commissionRecordId || typeof confirmed !== "boolean") {
      throw new HttpsError(
        "invalid-argument",
        "commissionRecordId and confirmed (boolean) are required."
      );
    }

    const db = getFirestore();
    const commRef = db.collection("commission_records").doc(commissionRecordId);
    const commSnap = await commRef.get();

    if (!commSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Commission record ${commissionRecordId} not found.`
      );
    }

    const comm = commSnap.data() as Record<string, unknown>;
    const bizId = comm.business_id as string | undefined;

    if (!bizId) {
      throw new HttpsError("internal", "Commission record missing business_id.");
    }

    // Verify ownership: business owner_auth_uid must match request.auth.uid (or admin)
    const bizSnap = await db.collection("businesses").doc(bizId).get();
    const biz = (bizSnap.data() || {}) as Record<string, unknown>;
    const isOwner = biz.owner_auth_uid === request.auth.uid;
    const isAdmin = request.auth.token?.role === "admin";

    if (!isOwner && !isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "You do not have permission to confirm payments for this business."
      );
    }

    const now = Timestamp.now();
    const updateData: Record<string, unknown> = {
      owner_confirmed: confirmed,
      owner_confirmed_at: now,
      owner_response: confirmed ? "confirmed" : "disputed",
    };

    let newStatus = comm.status as string;

    if (confirmed) {
      updateData.disputed = false;
      // If admin already confirmed, flip to verified!
      if (comm.admin_confirmed === true) {
        newStatus = "verified";
        updateData.status = "verified";
        updateData.date_verified = now;
      }
    } else {
      // Owner answered NO / Disputed
      updateData.disputed = true;
      updateData.dispute_reason = disputeReason ?? "Owner reported cash payment was not made";
      newStatus = "disputed";
      updateData.status = "disputed";
    }

    await commRef.update(updateData);

    logger.info("confirmCashPaymentOwner: processed", {
      commissionRecordId,
      confirmed,
      newStatus,
      ownerUid: request.auth.uid,
    });

    return {
      success: true,
      status: newStatus,
      adminConfirmed: comm.admin_confirmed ?? false,
      ownerConfirmed: confirmed,
    };
  }
);

// ---------------------------------------------------------------------------
// confirmCashPaymentAdmin — onCall (doc 06 / doc 04 stub)
// ---------------------------------------------------------------------------

/**
 * Admin action to confirm physical cash handoff/deposit.
 *
 * Input:
 *   - commissionRecordId: string (required)
 *   - notes?: string (optional)
 *
 * Logic:
 *   - Verifies caller has role == "admin".
 *   - Sets admin_confirmed = true, admin_confirmed_by = adminUid, admin_confirmed_at = now.
 *   - If owner_confirmed == true and not disputed → flips status to "verified", date_verified = now.
 */
export const confirmCashPaymentAdmin = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can approve commission records in the verification queue."
      );
    }

    const {commissionRecordId, notes} = (request.data || {}) as {
      commissionRecordId?: string;
      notes?: string;
    };

    if (!commissionRecordId) {
      throw new HttpsError(
        "invalid-argument",
        "commissionRecordId is required."
      );
    }

    const db = getFirestore();
    const commRef = db.collection("commission_records").doc(commissionRecordId);
    const commSnap = await commRef.get();

    if (!commSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Commission record ${commissionRecordId} not found.`
      );
    }

    const comm = commSnap.data() as Record<string, unknown>;
    const now = Timestamp.now();
    const updateData: Record<string, unknown> = {
      admin_confirmed: true,
      admin_confirmed_by: request.auth.uid,
      admin_confirmed_at: now,
    };

    if (notes) {
      updateData.admin_notes = notes;
    }

    let newStatus = comm.status as string;

    // Flip to verified ONLY if owner has confirmed and is not disputed
    if (comm.owner_confirmed === true && comm.disputed !== true) {
      newStatus = "verified";
      updateData.status = "verified";
      updateData.date_verified = now;
    }

    await commRef.update(updateData);

    logger.info("confirmCashPaymentAdmin: processed", {
      commissionRecordId,
      newStatus,
      adminUid: request.auth.uid,
    });

    return {
      success: true,
      status: newStatus,
      adminConfirmed: true,
      ownerConfirmed: comm.owner_confirmed ?? null,
    };
  }
);

// ---------------------------------------------------------------------------
// markCommissionPaidAdmin — onCall (doc 06 payout tracking)
// ---------------------------------------------------------------------------

/**
 * Marks a verified commission record as "paid".
 *
 * Input:
 *   - commissionRecordId: string (required)
 *   - payoutReference: string (required — transaction / UTR / receipt number)
 *
 * Constraints:
 *   - Only records with status == "verified" can be marked as paid.
 *   - Rejects unverified / pending / disputed records.
 */
export const markCommissionPaidAdmin = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can mark commission records as paid."
      );
    }

    const {commissionRecordId, payoutReference} = (request.data || {}) as {
      commissionRecordId?: string;
      payoutReference?: string;
    };

    if (!commissionRecordId || !payoutReference?.trim()) {
      throw new HttpsError(
        "invalid-argument",
        "commissionRecordId and payoutReference are required."
      );
    }

    const db = getFirestore();
    const commRef = db.collection("commission_records").doc(commissionRecordId);
    const commSnap = await commRef.get();

    if (!commSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Commission record ${commissionRecordId} not found.`
      );
    }

    const comm = commSnap.data() as Record<string, unknown>;
    if (comm.status !== "verified") {
      throw new HttpsError(
        "failed-precondition",
        `Cannot mark commission record as paid: current status is '${comm.status}' (must be 'verified').`
      );
    }

    const now = Timestamp.now();
    await commRef.update({
      status: "paid",
      payout_reference: payoutReference.trim(),
      date_paid: now,
    });

    logger.info("markCommissionPaidAdmin: processed", {
      commissionRecordId,
      payoutReference: payoutReference.trim(),
      adminUid: request.auth.uid,
    });

    return {success: true, status: "paid"};
  }
);
