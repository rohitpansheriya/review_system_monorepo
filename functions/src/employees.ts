/**
 * employees.ts — Admin Management of Employee Profiles & Offboarding
 *
 * Implements doc 04-admin-panel.md & 03-employee-enrollment-panel.md:
 *   - createEmployeeAccount: creates Auth account + sets role="employee" custom claim + creates employees/{uid}.
 *   - offboardEmployee: deactivates employee and bulk-updates all businesses where
 *     currently_managed_by == employeeUid to currently_managed_by = "admin", keeping enrolled_by_original.
 *   - verifyEmployeeDocumentsAdmin: sets documents_verified = "verified" / "rejected".
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

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

    const { email, password, displayName, phone, address } = (request.data || {}) as {
      email?: string;
      password?: string;
      displayName?: string;
      phone?: string;
      address?: string;
    };

    if (!email || !password || !displayName) {
      throw new HttpsError(
        "invalid-argument",
        "email, password, and displayName are required."
      );
    }

    const auth = getAuth();
    const db = getFirestore();

    // 1. Create Auth user
    const userRecord = await auth.createUser({
      email,
      password,
      displayName,
    });

    // 2. Set custom claim role="employee"
    await auth.setCustomUserClaims(userRecord.uid, { role: "employee" });

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
        address: address ?? "",
      },
      payout: {},
      documents: [],
    });

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

    const { employeeUid } = (request.data || {}) as {
      employeeUid?: string;
    };

    if (!employeeUid) {
      throw new HttpsError(
        "invalid-argument",
        "employeeUid is required."
      );
    }

    const db = getFirestore();

    // 1. Update employee doc status to "inactive"
    const empRef = db.collection("employees").doc(employeeUid);
    const empSnap = await empRef.get();

    if (!empSnap.exists) {
      throw new HttpsError("not-found", `Employee profile ${employeeUid} not found.`);
    }

    await empRef.update({
      status: "inactive",
      offboarded_at: Timestamp.now(),
      offboarded_by: request.auth.uid,
    });

    // 2. Bulk update all businesses currently managed by this employee
    //    sets currently_managed_by = "admin", keeps enrolled_by_original intact
    const bizSnap = await db
      .collection("businesses")
      .where("currently_managed_by", "==", employeeUid)
      .get();

    const batchSize = 400;
    let batch = db.batch();
    let count = 0;
    let totalUpdated = 0;

    for (const doc of bizSnap.docs) {
      batch.update(doc.ref, {
        currently_managed_by: "admin",
      });
      count++;
      totalUpdated++;

      if (count >= batchSize) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }

    logger.info("offboardEmployee: completed bulk update", {
      employeeUid,
      businessesReassignedToAdmin: totalUpdated,
      adminUid: request.auth.uid,
    });

    return {
      success: true,
      employeeUid,
      businessesReassignedToAdmin: totalUpdated,
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

    const { employeeUid, status, notes } = (request.data || {}) as {
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

    const updateData: Record<string, any> = {
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
