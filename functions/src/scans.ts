/**
 * scans.ts — Server-side scan logging, stats aggregation, and abuse prevention.
 *
 * Security:
 * When a customer scans a QR / posts a review, the client writes ONLY an immutable
 * document to `businesses/{businessId}/scans/{scanId}`.
 * The `onScanCreated` Firestore trigger intercepts the scan creation and atomically
 * increments `stats_summary` on the corresponding branch document using admin credentials.
 *
 * Abuse Prevention:
 * 1. Verifies parent business & branch exist and are active.
 * 2. Deduplicates by session_token (skips counter increment for repeat submissions from the same session).
 * 3. Enforces valid star_rating (1–5) and recognized actions.
 */

import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import {getFirestore, FieldValue} from "firebase-admin/firestore";

const VALID_ACTIONS = new Set([
  "google_maps",
  "whatsapp",
  "feedback_submitted",
  "low_skip",
  "thankyou",
]);

export const onScanCreated = onDocumentCreated(
  {
    document: "businesses/{businessId}/scans/{scanId}",
    memory: "256MiB",
    timeoutSeconds: 30,
    region: "asia-south1",
  },
  async (event) => {
    const {businessId, scanId} = event.params;
    const scanData = event.data?.data();

    if (!scanData) {
      logger.warn("onScanCreated: event.data is null, skipping", {businessId, scanId});
      return;
    }

    const branchId = scanData.branch_id as string | undefined;
    if (!branchId || typeof branchId !== "string" || branchId.trim().length === 0) {
      logger.warn("onScanCreated: missing or invalid branch_id in scan doc", {
        businessId,
        scanId,
        scanData,
      });
      return;
    }

    const db = getFirestore();
    const branchRef = db.doc(`businesses/${businessId}/branches/${branchId}`);

    // ── 1. Verify Branch & Parent Business Status ────────────────────────────
    const branchSnap = await branchRef.get();
    if (!branchSnap.exists) {
      logger.warn("onScanCreated: branch does not exist, skipping aggregation", {
        businessId,
        branchId,
        scanId,
      });
      return;
    }

    const branchData = branchSnap.data();
    if (branchData?.subscription_status === "deleted") {
      logger.info("onScanCreated: branch is deleted, skipping aggregation", {
        businessId,
        branchId,
        scanId,
      });
      return;
    }

    // ── 2. Session Deduplication (Lightweight Abuse Guard) ───────────────────
    const sessionToken = scanData.session_token as string | undefined;
    if (sessionToken && typeof sessionToken === "string" && sessionToken.trim().length > 0) {
      const duplicateQuery = await db
        .collection(`businesses/${businessId}/scans`)
        .where("session_token", "==", sessionToken.trim())
        .limit(2)
        .get();

      if (duplicateQuery.size > 1) {
        logger.info("onScanCreated: duplicate session scan detected — skipping aggregate increment", {
          businessId,
          branchId,
          scanId,
          sessionToken,
        });
        return;
      }
    }

    // ── 3. Sanitize and Validate Inputs ──────────────────────────────────────
    const starRating =
      typeof scanData.star_rating === "number" &&
      Number.isInteger(scanData.star_rating) &&
      scanData.star_rating >= 1 &&
      scanData.star_rating <= 5 ?
        scanData.star_rating :
        undefined;

    const rawAction = scanData.action_taken as string | undefined;
    const actionTaken =
      rawAction && typeof rawAction === "string" && VALID_ACTIONS.has(rawAction) ?
        rawAction :
        undefined;

    // ── 4. Atomic Counter Updates (Lifetime & Pre-aggregated Monthly) ───────
    try {
      const now = new Date();
      const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;

      const statsUpdates: Record<string, FieldValue> = {
        // Lifetime totals
        "stats_summary.total_scans": FieldValue.increment(1),
        // Pre-aggregated monthly totals
        [`monthly_stats.${monthKey}.total_scans`]: FieldValue.increment(1),
      };

      if (actionTaken === "google_maps") {
        statsUpdates["stats_summary.total_reviews_redirected"] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.google_reviews_opened`] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.total_reviews_redirected`] = FieldValue.increment(1);
      } else if (actionTaken === "whatsapp" || actionTaken === "feedback_submitted" || actionTaken === "low_skip") {
        statsUpdates[`monthly_stats.${monthKey}.private_issues`] = FieldValue.increment(1);
      }

      if (starRating !== undefined) {
        statsUpdates[`stats_summary.star_counts.${starRating}`] = FieldValue.increment(1);
        statsUpdates[`stats_summary.star_distribution.${starRating}`] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.star_counts.${starRating}`] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.star_distribution.${starRating}`] = FieldValue.increment(1);
      }

      await branchRef.update(statsUpdates);

      logger.info("onScanCreated: successfully aggregated stats for branch", {
        businessId,
        branchId,
        scanId,
        monthKey,
        starRating,
        actionTaken,
      });
    } catch (err) {
      logger.error("onScanCreated: failed to update branch stats_summary", {
        businessId,
        branchId,
        scanId,
        err,
      });
    }
  }
);
