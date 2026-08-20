/**
 * commissions.ts — Payment confirmation & Commission ledger
 *
 * RESTRUCTURED: Two separate concepts that were previously conflated:
 *
 *   A) PAYMENT (owner → Appnexa): ₹1999/₹999 subscription fee.
 *      Cash payments are a VIEW on businesses (payment_mode='cash' +
 *      subscription_status='pending_payment'). Admin confirms cash →
 *      business activates → auto-leaves the pending view.
 *
 *   B) COMMISSION (Appnexa → employee): ₹250 per activation.
 *      Stored in `employee_commissions` collection. Created automatically
 *      when a business activates (Firestore trigger). Employee-enrolled
 *      businesses only. Admin-enrolled = no commission.
 *      Status: 'pending' → 'paid'. NEVER deleted.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";

/**
 * Configurable per-activation commission amount (₹).
 * Change this single value to adjust employee commission across the platform.
 */
const EMPLOYEE_COMMISSION_AMOUNT = 250;

// ---------------------------------------------------------------------------
// confirmCashPaymentAdmin — onCall (Build A: Payment)
// ---------------------------------------------------------------------------

/**
 * Admin confirms physical cash receipt for a business.
 * This single action activates the business — no intermediate records.
 *
 * Input:
 *   - businessId: string (required) — the business to activate
 *   - notes?: string (optional)
 *
 * Logic:
 *   1. Verifies caller is admin.
 *   2. Verifies business exists and is pending_payment with payment_mode='cash'.
 *   3. Activates the business: status='active', renewal_date=+365, QR triggers.
 *   4. Business auto-leaves the pending-cash view.
 *
 * Commission is NOT created here — the onBusinessActivated trigger handles that.
 */
export const confirmCashPaymentAdmin = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can confirm cash payments."
      );
    }

    const {businessId, notes} = (request.data || {}) as {
      businessId?: string;
      notes?: string;
    };

    if (!businessId) {
      throw new HttpsError(
        "invalid-argument",
        "businessId is required."
      );
    }

    const db = getFirestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const bizSnap = await bizRef.get();

    if (!bizSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Business ${businessId} not found.`
      );
    }

    const bizData = bizSnap.data() as Record<string, unknown>;
    const currentStatus = bizData.subscription_status as string | undefined;
    const paymentMode = bizData.payment_mode as string | undefined;

    if (currentStatus !== "pending_payment") {
      throw new HttpsError(
        "failed-precondition",
        `Business is not pending_payment (current: '${currentStatus}'). Cannot confirm cash.`
      );
    }

    if (paymentMode && paymentMode !== "cash") {
      throw new HttpsError(
        "failed-precondition",
        `Business payment_mode is '${paymentMode}', not 'cash'. Use Razorpay for online payments.`
      );
    }

    const now = Timestamp.now();
    const renewalDate = new Date();
    renewalDate.setDate(renewalDate.getDate() + 365);

    const updateData: Record<string, unknown> = {
      subscription_status: "active",
      renewal_date: Timestamp.fromDate(renewalDate),
      payment_mode: "cash",
      cash_payment_confirmed_at: now,
      cash_confirmed_by_admin: request.auth.uid,
    };

    if (notes) {
      updateData.cash_confirm_notes = notes;
    }

    await bizRef.update(updateData);

    logger.info("confirmCashPaymentAdmin: business activated via cash", {
      businessId,
      adminUid: request.auth.uid,
      renewalDate: renewalDate.toISOString(),
    });

    return {
      success: true,
      businessId,
      status: "active",
      renewalDate: renewalDate.toISOString(),
    };
  }
);

// ---------------------------------------------------------------------------
// onBusinessActivated — Firestore Trigger (Build B: Commission)
// ---------------------------------------------------------------------------

/**
 * Triggered when a business document is updated.
 * If subscription_status changed to 'active' AND enrolled_by is a real
 * employee (not 'admin'), creates ONE employee_commissions entry.
 *
 * This handles BOTH cash and online activations uniformly:
 *   - Cash: confirmCashPaymentAdmin flips status → this trigger fires
 *   - Online: Razorpay webhook flips status → this trigger fires
 *
 * Guard: only fires on the FIRST activation (pending_payment → active).
 * Renewals (active → active) or reactivations are ignored.
 */
export const onBusinessActivated = onDocumentUpdated(
  {
    document: "businesses/{businessId}",
    region: "asia-south1",
  },
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();
    if (!beforeData || !afterData) return;

    const beforeStatus = beforeData.subscription_status as string | undefined;
    const afterStatus = afterData.subscription_status as string | undefined;

    // Only trigger on pending_payment → active transition
    if (beforeStatus !== "pending_payment" || afterStatus !== "active") return;

    const businessId = event.params.businessId;
    const enrolledBy = afterData.enrolled_by as string | undefined;

    // Admin-enrolled businesses generate NO employee commission
    if (!enrolledBy || enrolledBy === "admin" || enrolledBy === "") {
      logger.info("onBusinessActivated: admin-enrolled, no commission", {
        businessId,
        enrolledBy,
      });
      return;
    }

    const db = getFirestore();
    const now = Timestamp.now();
    const activationDate = now.toDate();
    const activationMonth = `${activationDate.getFullYear()}-${String(activationDate.getMonth() + 1).padStart(2, "0")}`;

    // Idempotency: use deterministic doc ID to prevent duplicates on retries
    const commDocId = `comm_${businessId}`;
    const commRef = db.collection("employee_commissions").doc(commDocId);

    // Check if already exists (idempotency guard)
    const existing = await commRef.get();
    if (existing.exists) {
      logger.info("onBusinessActivated: commission already exists, skipping", {
        businessId, commDocId,
      });
      return;
    }

    const businessName = afterData.brand_name as string || "";

    await commRef.set({
      employee_id: enrolledBy,
      business_id: businessId,
      business_name: businessName,
      amount: EMPLOYEE_COMMISSION_AMOUNT,
      status: "pending",
      created_at: now,
      activation_month: activationMonth,
      paid_at: null,
      paid_by: null,
      payout_reference: null,
    });

    // Increment employee counters
    const empRef = db.collection("employees").doc(enrolledBy);
    try {
      await empRef.update({
        total_commissions_earned: FieldValue.increment(EMPLOYEE_COMMISSION_AMOUNT),
      });
    } catch (e) {
      logger.warn("onBusinessActivated: employee counter update failed", {
        employeeId: enrolledBy, error: e,
      });
    }

    logger.info("onBusinessActivated: commission created", {
      businessId,
      employeeId: enrolledBy,
      amount: EMPLOYEE_COMMISSION_AMOUNT,
      activationMonth,
      commDocId,
    });
  }
);

// ---------------------------------------------------------------------------
// markCommissionsPaidBulk — onCall (Build B: Commission Payout)
// ---------------------------------------------------------------------------

/**
 * Admin marks ALL pending commissions for a given employee + month as 'paid'.
 * One-click payout action.
 *
 * Input:
 *   - employeeId: string (required)
 *   - month: string (required — 'YYYY-MM' format)
 *   - payoutReference: string (required — UTR / transaction ID)
 *
 * Logic:
 *   1. Queries employee_commissions where employee_id=X, activation_month=Y, status='pending'.
 *   2. Batch-updates all to status='paid' with payout details.
 *   3. Returns count of records updated.
 */
export const markCommissionsPaidBulk = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can mark commissions as paid."
      );
    }

    const {employeeId, month, payoutReference} = (request.data || {}) as {
      employeeId?: string;
      month?: string;
      payoutReference?: string;
    };

    if (!employeeId || !month || !payoutReference?.trim()) {
      throw new HttpsError(
        "invalid-argument",
        "employeeId, month (YYYY-MM), and payoutReference are required."
      );
    }

    // Validate month format
    if (!/^\d{4}-\d{2}$/.test(month)) {
      throw new HttpsError(
        "invalid-argument",
        "month must be in 'YYYY-MM' format."
      );
    }

    const db = getFirestore();
    const snapshot = await db
      .collection("employee_commissions")
      .where("employee_id", "==", employeeId)
      .where("activation_month", "==", month)
      .where("status", "==", "pending")
      .get();

    if (snapshot.empty) {
      return {
        success: true,
        count: 0,
        message: "No pending commissions found for this employee and month.",
      };
    }

    const now = Timestamp.now();
    const batch = db.batch();
    let count = 0;

    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        status: "paid",
        paid_at: now,
        paid_by: request.auth.uid,
        payout_reference: payoutReference.trim(),
      });
      count++;
    }

    await batch.commit();

    logger.info("markCommissionsPaidBulk: processed", {
      employeeId,
      month,
      count,
      payoutReference: payoutReference.trim(),
      adminUid: request.auth.uid,
    });

    return {
      success: true,
      count,
      totalAmount: count * EMPLOYEE_COMMISSION_AMOUNT,
    };
  }
);
