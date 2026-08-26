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
import {buildQrForBranch, buildPlainQrForBranch} from "./qrGenerator.js";
import {provisionOwnerAccount} from "./razorpay.js";

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

    const branchesSnap = await bizRef.collection("branches").get();
    const batch = db.batch();
    batch.update(bizRef, updateData);

    for (const branchDoc of branchesSnap.docs) {
      batch.update(branchDoc.ref, {
        subscription_status: "active",
        payment_mode: "cash",
        cash_payment_confirmed_at: now,
        cash_confirmed_by_admin: request.auth.uid,
        activated_at: now,
        standee_status: "not_ordered",
        standee_status_updated_at: now,
      });
    }

    await batch.commit();

    // Provision owner Firebase Auth account
    const ownerEmail = bizData.owner_email as string | undefined;
    const ownerName = bizData.owner_name as string | undefined;
    if (ownerEmail && !bizData.owner_auth_uid) {
      try {
        await provisionOwnerAccount(db, businessId, ownerEmail, ownerName);
      } catch (provErr) {
        logger.error("confirmCashPaymentAdmin: provisionOwnerAccount error", {
          businessId,
          ownerEmail,
          provErr,
        });
      }
    }

    logger.info("confirmCashPaymentAdmin: business and branches activated via cash", {
      businessId,
      branchCount: branchesSnap.size,
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
// adminCashActivateBranch — onCall (Branch-Level Cash Payment)
// ---------------------------------------------------------------------------

/**
 * Admin confirms physical cash receipt for a specific branch (₹1999).
 * Input:
 *   - businessId: string (required)
 *   - branchId: string (required)
 *   - notes?: string (optional)
 */
export const adminCashActivateBranch = onCall(
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

    const {businessId, branchId, notes} = (request.data || {}) as {
      businessId?: string;
      branchId?: string;
      notes?: string;
    };

    if (!businessId || !branchId) {
      throw new HttpsError(
        "invalid-argument",
        "businessId and branchId are required."
      );
    }

    const db = getFirestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const branchRef = bizRef.collection("branches").doc(branchId);

    const [bizSnap, branchSnap] = await Promise.all([bizRef.get(), branchRef.get()]);

    if (!bizSnap.exists) {
      throw new HttpsError("not-found", `Business ${businessId} not found.`);
    }
    if (!branchSnap.exists) {
      throw new HttpsError("not-found", `Branch ${branchId} not found.`);
    }

    const branchData = branchSnap.data() as Record<string, unknown>;
    const bizData = bizSnap.data() as Record<string, unknown>;

    const currentStatus = branchData.subscription_status as string | undefined;
    if (currentStatus === "active") {
      throw new HttpsError(
        "failed-precondition",
        "Branch is already active."
      );
    }

    const now = Timestamp.now();
    const updateData: Record<string, unknown> = {
      subscription_status: "active",
      payment_mode: "cash",
      cash_payment_confirmed_at: now,
      cash_confirmed_by_admin: request.auth.uid,
      activated_at: now,
      standee_status: "not_ordered",
      standee_status_updated_at: now,
    };

    if (notes) {
      updateData.cash_confirm_notes = notes;
    }

    await branchRef.update(updateData);

    // If parent business is pending_payment, also activate parent business
    if (bizData.subscription_status === "pending_payment") {
      const renewalDate = new Date();
      renewalDate.setDate(renewalDate.getDate() + 365);
      await bizRef.update({
        subscription_status: "active",
        renewal_date: Timestamp.fromDate(renewalDate),
        payment_mode: "cash",
        cash_payment_confirmed_at: now,
        cash_confirmed_by_admin: request.auth.uid,
      });
    }

    // QR generation
    try {
      await buildQrForBranch(businessId, branchId, branchRef);
      await buildPlainQrForBranch(businessId, branchId, branchRef);
    } catch (qrErr) {
      logger.error("adminCashActivateBranch: QR generation failed", {businessId, branchId, qrErr});
    }

    // Commission creation if enrolled by an employee
    const enrolledBy = (branchData.enrolled_by as string | undefined) || (bizData.enrolled_by as string | undefined);
    if (enrolledBy && enrolledBy !== "admin") {
      const commDocId = `comm_${businessId}_${branchId}_first_activation`;
      const commRef = db.collection("employee_commissions").doc(commDocId);
      const commSnap = await commRef.get();
      if (!commSnap.exists) {
        const activationMonth = new Date().toISOString().slice(0, 7);
        const branchName = branchData.branch_name as string | undefined ?? "Branch";
        const brandName = bizData.brand_name as string | undefined ?? "Business";
        await commRef.set({
          employee_id: enrolledBy,
          business_id: businessId,
          branch_id: branchId,
          business_name: `${brandName} (${branchName})`,
          amount: EMPLOYEE_COMMISSION_AMOUNT,
          status: "pending",
          created_at: now,
          activation_month: activationMonth,
          paid_at: null,
          paid_by: null,
          payout_reference: null,
        });

        const empRef = db.collection("employees").doc(enrolledBy);
        try {
          await empRef.update({
            total_commissions_earned: FieldValue.increment(EMPLOYEE_COMMISSION_AMOUNT),
            total_enrollments: FieldValue.increment(1),
            this_month_enrollments: FieldValue.increment(1),
          });
        } catch (e) {
          logger.warn("adminCashActivateBranch: employee counter update failed", {employeeId: enrolledBy, error: e});
        }
      }
    }

    return {
      success: true,
      businessId,
      branchId,
      status: "active",
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

    // ── QR generation for ALL activations (admin + employee enrolled) ──
    // The onBranchCreated trigger skips QR for pending_payment drafts,
    // and only the Razorpay webhook generates QR inline. Cash-activated
    // businesses (both admin and employee) would otherwise never get QR.
    // Generate here for every activation path uniformly.
    const db = getFirestore();
    let branchesSnap: FirebaseFirestore.QuerySnapshot | undefined;
    try {
      branchesSnap = await db
        .collection(`businesses/${businessId}/branches`)
        .get();
      logger.info("onBusinessActivated: generating QR for branches", {
        businessId, branchCount: branchesSnap.size,
      });
      for (const branchDoc of branchesSnap.docs) {
        // Standee QR (branded, print-ready)
        try {
          const result = await buildQrForBranch(
            businessId,
            branchDoc.id,
            branchDoc.ref
          );
          logger.info("onBusinessActivated: standee QR generated", {
            businessId, branchId: branchDoc.id, qrPath: result.qrStoragePath,
          });
        } catch (branchErr) {
          logger.error("onBusinessActivated: standee QR failed for branch", {
            businessId, branchId: branchDoc.id, err: branchErr,
          });
        }
        // Plain printable QR
        try {
          const plainResult = await buildPlainQrForBranch(
            businessId,
            branchDoc.id,
            branchDoc.ref
          );
          logger.info("onBusinessActivated: plain QR generated", {
            businessId, branchId: branchDoc.id, path: plainResult.plainQrStoragePath,
          });
        } catch (plainErr) {
          logger.error("onBusinessActivated: plain QR failed for branch", {
            businessId, branchId: branchDoc.id, err: plainErr,
          });
        }
      }
    } catch (err) {
      logger.error("onBusinessActivated: failed to read branches for QR", {
        businessId, err,
      });
    }

    // Admin-enrolled businesses generate NO employee commission
    if (!enrolledBy || enrolledBy === "admin" || enrolledBy === "") {
      logger.info("onBusinessActivated: admin-enrolled, no commission", {
        businessId,
        enrolledBy,
      });
      return;
    }

    const empRef = db.collection("employees").doc(enrolledBy);
    const empSnap = await empRef.get();
    if (!empSnap.exists) {
      logger.info("onBusinessActivated: enrolledBy is not an employee profile, skipping commission", {
        businessId,
        enrolledBy,
      });
      return;
    }

    // If branches exist, onBranchActivated creates per-branch commission records.
    // Only create fallback comm_${businessId} if branches subcollection is empty.
    if (branchesSnap && !branchesSnap.empty) {
      logger.info("onBusinessActivated: branches exist, per-branch commissions handled by onBranchActivated", {
        businessId,
        branchCount: branchesSnap.size,
      });
      return;
    }

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
// onBranchActivated — Firestore Trigger (Branch Commission & QR Trigger)
// ---------------------------------------------------------------------------

/**
 * Triggered when a branch document is updated.
 * If subscription_status changed to 'active' AND enrolled_by is a real
 * employee (not 'admin'), generates QR codes and creates ONE employee_commissions entry.
 */
export const onBranchActivated = onDocumentUpdated(
  {
    document: "businesses/{businessId}/branches/{branchId}",
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

    const {businessId, branchId} = event.params;
    const db = getFirestore();

    const branchRef = event.data?.after.ref;
    if (branchRef && !afterData.qr_code_id) {
      try {
        await buildQrForBranch(businessId, branchId, branchRef);
        await buildPlainQrForBranch(businessId, branchId, branchRef);
      } catch (qrErr) {
        logger.error("onBranchActivated: QR generation failed", {businessId, branchId, qrErr});
      }
    }

    const bizSnap = await db.doc(`businesses/${businessId}`).get();
    const bizData = bizSnap.data() as Record<string, unknown> | undefined;
    const enrolledBy = (afterData.enrolled_by as string | undefined) || (bizData?.enrolled_by as string | undefined);

    if (enrolledBy && enrolledBy !== "admin") {
      const empRef = db.collection("employees").doc(enrolledBy);
      const empSnap = await empRef.get();
      if (!empSnap.exists) {
        logger.info("onBranchActivated: enrolledBy is not an employee profile, skipping commission", {
          businessId,
          branchId,
          enrolledBy,
        });
        return;
      }

      const commDocId = `comm_${businessId}_${branchId}_first_activation`;
      const commRef = db.collection("employee_commissions").doc(commDocId);
      const commSnap = await commRef.get();
      if (!commSnap.exists) {
        const now = Timestamp.now();
        const activationMonth = new Date().toISOString().slice(0, 7);
        const branchName = (afterData.branch_name as string | undefined) ?? "Branch";
        const brandName = (bizData?.brand_name as string | undefined) ?? "Business";
        await commRef.set({
          employee_id: enrolledBy,
          business_id: businessId,
          branch_id: branchId,
          business_name: `${brandName} (${branchName})`,
          amount: EMPLOYEE_COMMISSION_AMOUNT,
          status: "pending",
          created_at: now,
          activation_month: activationMonth,
          paid_at: null,
          paid_by: null,
          payout_reference: null,
        });

        const empRef = db.collection("employees").doc(enrolledBy);
        try {
          await empRef.update({
            total_commissions_earned: FieldValue.increment(EMPLOYEE_COMMISSION_AMOUNT),
            total_enrollments: FieldValue.increment(1),
            this_month_enrollments: FieldValue.increment(1),
          });
        } catch (e) {
          logger.warn("onBranchActivated: employee counter update failed", {employeeId: enrolledBy, error: e});
        }

        logger.info("onBranchActivated: commission created", {
          businessId,
          branchId,
          employeeId: enrolledBy,
          amount: EMPLOYEE_COMMISSION_AMOUNT,
          activationMonth,
          commDocId,
        });
      }
    }
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

// ---------------------------------------------------------------------------
// 7. adminRevertBusinessActivation (Callable — Admin only)
// ---------------------------------------------------------------------------
export const adminRevertBusinessActivation = onCall(
  {region: "asia-south1"},
  async (request): Promise<{success: boolean; businessId: string}> => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError("permission-denied", "Only admins can revert activations.");
    }

    const {businessId, reason} = (request.data || {}) as {
      businessId?: string;
      reason?: string;
    };

    if (!businessId || typeof businessId !== "string") {
      throw new HttpsError("invalid-argument", "businessId is required.");
    }

    const db = getFirestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const bizSnap = await bizRef.get();
    if (!bizSnap.exists) {
      throw new HttpsError("not-found", `Business ${businessId} not found.`);
    }

    const now = Timestamp.now();
    const batch = db.batch();

    batch.update(bizRef, {
      subscription_status: "pending_payment",
      payment_mode: "pending",
      reverted_at: now,
      reverted_by: request.auth.uid,
      revert_reason: reason || null,
    });

    // Revert all branches
    const branchesSnap = await bizRef.collection("branches").get();
    for (const branchDoc of branchesSnap.docs) {
      batch.update(branchDoc.ref, {
        subscription_status: "pending_payment",
        payment_mode: "pending",
        reverted_at: now,
        reverted_by: request.auth.uid,
      });
    }

    // Cancel pending commissions associated with this business
    const commSnap = await db
      .collection("employee_commissions")
      .where("business_id", "==", businessId)
      .where("status", "==", "pending")
      .get();

    for (const commDoc of commSnap.docs) {
      const commData = commDoc.data();
      const empId = commData.employee_id as string;
      batch.update(commDoc.ref, {
        status: "cancelled",
        cancelled_at: now,
        cancelled_by: request.auth.uid,
        cancel_reason: reason || "Activation reverted by admin",
      });

      if (empId) {
        const empRef = db.collection("employees").doc(empId);
        batch.update(empRef, {
          total_commissions_earned: FieldValue.increment(-EMPLOYEE_COMMISSION_AMOUNT),
          total_enrollments: FieldValue.increment(-1),
          this_month_enrollments: FieldValue.increment(-1),
        });
      }
    }

    await batch.commit();

    logger.info("adminRevertBusinessActivation: success", {
      businessId,
      adminUid: request.auth.uid,
      reason,
    });

    return {success: true, businessId};
  }
);

// ---------------------------------------------------------------------------
// 8. adminRevertBranchActivation (Callable — Admin only)
// ---------------------------------------------------------------------------
export const adminRevertBranchActivation = onCall(
  {region: "asia-south1"},
  async (request): Promise<{success: boolean; businessId: string; branchId: string}> => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError("permission-denied", "Only admins can revert activations.");
    }

    const {businessId, branchId, reason} = (request.data || {}) as {
      businessId?: string;
      branchId?: string;
      reason?: string;
    };

    if (!businessId || !branchId) {
      throw new HttpsError("invalid-argument", "businessId and branchId are required.");
    }

    const db = getFirestore();
    const branchRef = db
      .collection("businesses")
      .doc(businessId)
      .collection("branches")
      .doc(branchId);

    const branchSnap = await branchRef.get();
    if (!branchSnap.exists) {
      throw new HttpsError("not-found", `Branch ${branchId} not found.`);
    }

    const now = Timestamp.now();
    const batch = db.batch();

    batch.update(branchRef, {
      subscription_status: "pending_payment",
      payment_mode: "pending",
      reverted_at: now,
      reverted_by: request.auth.uid,
      revert_reason: reason || null,
    });

    // Cancel pending commissions for this specific branch
    const commSnap = await db
      .collection("employee_commissions")
      .where("branch_id", "==", branchId)
      .where("status", "==", "pending")
      .get();

    for (const commDoc of commSnap.docs) {
      const commData = commDoc.data();
      const empId = commData.employee_id as string;
      batch.update(commDoc.ref, {
        status: "cancelled",
        cancelled_at: now,
        cancelled_by: request.auth.uid,
        cancel_reason: reason || "Branch activation reverted by admin",
      });

      if (empId) {
        const empRef = db.collection("employees").doc(empId);
        batch.update(empRef, {
          total_commissions_earned: FieldValue.increment(-EMPLOYEE_COMMISSION_AMOUNT),
          total_enrollments: FieldValue.increment(-1),
          this_month_enrollments: FieldValue.increment(-1),
        });
      }
    }

    await batch.commit();

    logger.info("adminRevertBranchActivation: success", {
      businessId,
      branchId,
      adminUid: request.auth.uid,
      reason,
    });

    return {success: true, businessId, branchId};
  }
);

