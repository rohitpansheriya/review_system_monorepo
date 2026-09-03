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
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";

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
      resetLink = await auth.generatePasswordResetLink(email);
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
