/**
 * employees.ts — Admin Management of Employee Profiles & Offboarding
 *
 * Implements doc 04-admin-panel.md & 03-employee-enrollment-panel.md:
 *   - createEmployeeAccount: creates Auth account + sets role="employee" custom claim + creates employees/{uid}.
 *   - offboardEmployee: deactivates employee and bulk-updates all businesses where
 *     currently_managed_by == employeeUid to currently_managed_by = "admin", keeping enrolled_by_original.
 *   - verifyEmployeeDocumentsAdmin: sets documents_verified = "verified" / "rejected".
 */

import * as crypto from "crypto";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {formatCustomResetLink} from "./notifications";

// ---------------------------------------------------------------------------
// createEmployeeAccount — onCall (doc 04)
// ---------------------------------------------------------------------------

export const createEmployeeAccount = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can create employee profiles."
      );
    }

    const {email, password, displayName, phone, address} = (request.data || {}) as {
      email?: string;
      password?: string;
      displayName?: string;
      phone?: string;
      address?: string;
    };

    if (!email || !displayName) {
      throw new HttpsError(
        "invalid-argument",
        "email and displayName are required."
      );
    }

    const auth = getAuth();
    const db = getFirestore();

    // Generate secure temporary random password if admin did not provide one
    const tempPassword = password || `${crypto.randomBytes(16).toString("hex")}!Aa1`;

    // 1. Create Auth user
    const userRecord = await auth.createUser({
      email,
      password: tempPassword,
      displayName,
    });

    // 2. Set custom claim role="employee"
    await auth.setCustomUserClaims(userRecord.uid, {role: "employee"});

    // 3. Create employees/{uid} document
    const now = Timestamp.now();
    await db.collection("employees").doc(userRecord.uid).set({
      name: displayName,
      email: email,
      phone: phone ?? "",
      role: "employee",
      status: "active",
      total_enrollments: 0,
      this_month_enrollments: 0,
      documents_verified: "pending",
      created_at: now,
      profile: {
        full_name: displayName,
        email: email,
        phone: phone ?? "",
        address: address ?? "",
      },
      payout: {},
      documents: [],
    });

    // 4. Generate password-set/reset link so employee sets their own password
    let resetLink: string | null = null;
    try {
      const rawLink = await auth.generatePasswordResetLink(email);
      resetLink = formatCustomResetLink(rawLink);
      logger.info("createEmployeeAccount: password setup link generated", {
        employeeUid: userRecord.uid,
        email,
        resetLink,
      });
    } catch (err) {
      logger.warn("createEmployeeAccount: password reset link generation warning", {err});
    }

    logger.info("createEmployeeAccount: created", {
      employeeUid: userRecord.uid,
      email,
      adminUid: request.auth.uid,
    });

    return {
      success: true,
      employeeUid: userRecord.uid,
      email,
      name: displayName,
      resetLink,
    };
  }
);

// ---------------------------------------------------------------------------
// offboardEmployee — onCall (doc 04 & 00/03)
// ---------------------------------------------------------------------------

export const offboardEmployee = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can offboard/deactivate employees."
      );
    }

    const {employeeUid} = (request.data || {}) as {
      employeeUid?: string;
    };

    if (!employeeUid) {
      throw new HttpsError(
        "invalid-argument",
        "employeeUid is required."
      );
    }

    const db = getFirestore();

    // 1. Update employee doc status to "inactive" and active = false
    const empRef = db.collection("employees").doc(employeeUid);
    const empSnap = await empRef.get();

    if (!empSnap.exists) {
      throw new HttpsError("not-found", `Employee profile ${employeeUid} not found.`);
    }

    await empRef.update({
      active: false,
      status: "inactive",
      offboarded_at: Timestamp.now(),
      offboarded_by: request.auth.uid,
    });

    // 2. Disable Firebase Auth account so employee can no longer log in
    try {
      const auth = getAuth();
      await auth.updateUser(employeeUid, {disabled: true});
      await auth.revokeRefreshTokens(employeeUid);
      logger.info("offboardEmployee: employee Auth account disabled", {employeeUid});
    } catch (authErr) {
      logger.warn("offboardEmployee: could not disable Auth account (may be test UID or non-existent in Auth)", {
        employeeUid,
        authErr,
      });
    }

    // 3. Enrolled businesses remain intact with enrolled_by = employeeUid.
    // Admin manages all businesses directly via All-Businesses screen.
    // No employee-to-employee reassignment is performed, and historical commission records are preserved.
    logger.info("offboardEmployee: employee deactivated successfully", {
      employeeUid,
      adminUid: request.auth.uid,
    });

    return {
      success: true,
      employeeUid,
    };
  }
);

// ---------------------------------------------------------------------------
// verifyEmployeeDocumentsAdmin — onCall (doc 04)
// ---------------------------------------------------------------------------

export const verifyEmployeeDocumentsAdmin = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can verify employee documents."
      );
    }

    const {employeeUid, status, notes} = (request.data || {}) as {
      employeeUid?: string;
      status?: string;
      notes?: string;
    };

    if (!employeeUid || !status || !["verified", "rejected", "pending"].includes(status)) {
      throw new HttpsError(
        "invalid-argument",
        "employeeUid and valid status ('verified'|'rejected'|'pending') are required."
      );
    }

    const db = getFirestore();
    const empRef = db.collection("employees").doc(employeeUid);

    const updateData: Record<string, unknown> = {
      documents_verified: status,
      documents_verified_at: Timestamp.now(),
      documents_verified_by: request.auth.uid,
    };
    if (notes) {
      updateData.verification_notes = notes;
    }

    await empRef.update(updateData);

    logger.info("verifyEmployeeDocumentsAdmin: updated", {
      employeeUid,
      status,
      adminUid: request.auth.uid,
    });

    return {
      success: true,
      employeeUid,
      status,
    };
  }
);

// ---------------------------------------------------------------------------
// reassignBusinessEnrollerAdmin — onCall
// ---------------------------------------------------------------------------

export const reassignBusinessEnrollerAdmin = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth?.uid || request.auth.token?.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can change the enrolled employee of a business."
      );
    }

    const {businessId, newEmployeeUid, reason} = (request.data || {}) as {
      businessId?: string;
      newEmployeeUid?: string;
      reason?: string;
    };

    if (!businessId || !newEmployeeUid) {
      throw new HttpsError(
        "invalid-argument",
        "businessId and newEmployeeUid are required."
      );
    }

    const db = getFirestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const bizSnap = await bizRef.get();

    if (!bizSnap.exists) {
      throw new HttpsError("not-found", `Business ${businessId} not found.`);
    }

    const bizData = bizSnap.data() || {};
    const oldEnrolledBy = (bizData.enrolled_by as string | undefined) || "";
    const isBusinessActive = bizData.subscription_status === "active";
    const now = Timestamp.now();

    // Verify new employee exists if not "admin"
    let newEmployeeName = "Admin";
    if (newEmployeeUid !== "admin") {
      const empSnap = await db.collection("employees").doc(newEmployeeUid).get();
      if (!empSnap.exists) {
        throw new HttpsError("not-found", `Target employee ${newEmployeeUid} not found.`);
      }
      const empData = empSnap.data() || {};
      newEmployeeName = empData.name || (empData.profile?.full_name as string) || newEmployeeUid;
    }

    const batch = db.batch();

    // 1. Update business document
    batch.update(bizRef, {
      enrolled_by: newEmployeeUid,
      currently_managed_by: newEmployeeUid,
      updated_at: now,
      enroller_reassigned_at: now,
      enroller_reassigned_by: request.auth.uid,
      enroller_reassignment_reason: reason || "Admin manual reassignment",
    });

    // 2. Update branches
    const branchesSnap = await bizRef.collection("branches").get();
    for (const bDoc of branchesSnap.docs) {
      batch.update(bDoc.ref, {
        enrolled_by: newEmployeeUid,
      });
    }

    // 3. Update or create employee_commissions for this business
    const commSnap = await db
      .collection("employee_commissions")
      .where("business_id", "==", businessId)
      .get();

    if (!commSnap.empty) {
      for (const cDoc of commSnap.docs) {
        const cData = cDoc.data();
        if (cData.status === "pending") {
          if (newEmployeeUid === "admin") {
            // Admin doesn't receive employee commissions -> delete pending record
            batch.delete(cDoc.ref);
          } else {
            batch.update(cDoc.ref, {
              employee_id: newEmployeeUid,
              transferred_from: oldEnrolledBy || null,
              transferred_at: now,
            });
          }
        }
      }
    } else if (newEmployeeUid !== "admin" && isBusinessActive) {
      // Business was originally enrolled by admin (no commissions created).
      // Now reassigned to a real employee -> create the pending commission record(s)!
      const activationDate = now.toDate();
      const activationMonth = `${activationDate.getFullYear()}-${String(activationDate.getMonth() + 1).padStart(2, "0")}`;
      const brandName = (bizData.brand_name as string) || "Business";

      if (!branchesSnap.empty) {
        for (const bDoc of branchesSnap.docs) {
          const bData = bDoc.data();
          if (bData.subscription_status === "active" || isBusinessActive) {
            const commDocId = `comm_${businessId}_${bDoc.id}_first_activation`;
            const commRef = db.collection("employee_commissions").doc(commDocId);
            const branchName = (bData.branch_name as string) || "Branch";
            batch.set(commRef, {
              employee_id: newEmployeeUid,
              business_id: businessId,
              branch_id: bDoc.id,
              business_name: `${brandName} (${branchName})`,
              amount: 1000,
              status: "pending",
              created_at: now,
              activation_month: activationMonth,
              paid_at: null,
              paid_by: null,
              payout_reference: null,
              transferred_from: oldEnrolledBy || "admin",
              transferred_at: now,
            });
          }
        }
      } else {
        const commDocId = `comm_${businessId}`;
        const commRef = db.collection("employee_commissions").doc(commDocId);
        batch.set(commRef, {
          employee_id: newEmployeeUid,
          business_id: businessId,
          business_name: brandName,
          amount: 1000,
          status: "pending",
          created_at: now,
          activation_month: activationMonth,
          paid_at: null,
          paid_by: null,
          payout_reference: null,
          transferred_from: oldEnrolledBy || "admin",
          transferred_at: now,
        });
      }
    }

    await batch.commit();

    // 4. Update employee stats if business is active
    if (isBusinessActive) {
      if (oldEnrolledBy && oldEnrolledBy !== "admin" && oldEnrolledBy !== newEmployeeUid) {
        try {
          await db.collection("employees").doc(oldEnrolledBy).update({
            total_enrollments: FieldValue.increment(-1),
            this_month_enrollments: FieldValue.increment(-1),
          });
        } catch (e) {
          logger.warn("reassignBusinessEnrollerAdmin: old employee counter decrement error", {e});
        }
      }

      if (newEmployeeUid !== "admin" && newEmployeeUid !== oldEnrolledBy) {
        try {
          await db.collection("employees").doc(newEmployeeUid).update({
            total_enrollments: FieldValue.increment(1),
            this_month_enrollments: FieldValue.increment(1),
          });
        } catch (e) {
          logger.warn("reassignBusinessEnrollerAdmin: new employee counter increment error", {e});
        }
      }
    }

    logger.info("reassignBusinessEnrollerAdmin: reassigned business", {
      businessId,
      oldEnrolledBy,
      newEmployeeUid,
      newEmployeeName,
      adminUid: request.auth.uid,
    });

    return {
      success: true,
      businessId,
      oldEnrolledBy,
      newEmployeeUid,
      newEmployeeName,
    };
  }
);

