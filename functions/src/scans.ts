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
import {onCall, HttpsError} from "firebase-functions/v2/https";
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
    if (
      branchData?.subscription_status === "suspended" ||
      branchData?.subscription_status === "deleted"
    ) {
      logger.info("onScanCreated: branch is suspended/deleted, skipping aggregation", {
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
        .limit(3)
        .get();

      if (duplicateQuery.size > 2) {
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
        statsUpdates["stats_summary.google_reviews_opened"] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.google_reviews_opened`] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.total_reviews_redirected`] = FieldValue.increment(1);
      } else if (actionTaken === "whatsapp" || actionTaken === "feedback_submitted" || actionTaken === "low_skip") {
        statsUpdates["stats_summary.private_issues"] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.private_issues`] = FieldValue.increment(1);
      }

      if (starRating !== undefined) {
        statsUpdates[`stats_summary.star_counts.${starRating}`] = FieldValue.increment(1);
        statsUpdates[`stats_summary.star_distribution.${starRating}`] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.star_counts.${starRating}`] = FieldValue.increment(1);
        statsUpdates[`monthly_stats.${monthKey}.star_distribution.${starRating}`] = FieldValue.increment(1);
      }

      const bizRef = db.doc(`businesses/${businessId}`);

      // Use update() so dot-notation keys correctly target nested Firestore maps
      await Promise.all([
        branchRef.update(statsUpdates).catch(async (updateErr) => {
          logger.warn("onScanCreated: branch update failed, falling back to set", {branchId, updateErr});
          await branchRef.set(statsUpdates, {merge: true});
        }),
        bizRef.update(statsUpdates).catch(async (bizUpdateErr) => {
          logger.warn("onScanCreated: biz update failed, falling back to set", {businessId, bizUpdateErr});
          await bizRef.set(statsUpdates, {merge: true});
        }),
      ]);

      // ── 5. Auto-Promote Standee from 'shipped' to 'delivered' on Field Scan ──
      if (branchData?.standee_status === "shipped") {
        const shippedAt = branchData?.shipped_at as {toDate?: () => Date} | undefined;
        const shippedDate = shippedAt?.toDate ? shippedAt.toDate() : null;
        const isAfterDispatch = !shippedDate || (new Date() >= shippedDate);
        if (isAfterDispatch) {
          await branchRef.update({
            standee_status: "delivered",
            standee_status_updated_at: FieldValue.serverTimestamp(),
            delivered_at: FieldValue.serverTimestamp(),
            delivered_via: "first_scan_detected",
          });
          logger.info("onScanCreated: auto-promoted standee from shipped to delivered on live scan", {
            businessId,
            branchId,
            scanId,
          });
        }
      }

      logger.info("onScanCreated: successfully aggregated stats for branch and business rollup", {
        businessId,
        branchId,
        scanId,
        monthKey,
        starRating,
        actionTaken,
      });
    } catch (err) {
      logger.error("onScanCreated: failed to update branch/business stats_summary", {
        businessId,
        branchId,
        scanId,
        err,
      });
    }
  }
);

/**
 * Callable Function: reconcileBusinessStats
 * Reconciles and synchronizes stats_summary and monthly_stats directly from
 * the scans subcollection for a given business to fix any historic lag or TTL issues.
 */
export const reconcileBusinessStats = onCall(
  {
    region: "asia-south1",
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    const {businessId} = (request.data || {}) as {businessId?: string};
    if (!businessId || typeof businessId !== "string") {
      throw new HttpsError("invalid-argument", "businessId is required.");
    }

    const db = getFirestore();
    const bizRef = db.collection("businesses").doc(businessId);
    const bizSnap = await bizRef.get();
    if (!bizSnap.exists) {
      throw new HttpsError("not-found", `Business ${businessId} not found.`);
    }

    const scansSnap = await bizRef.collection("scans").get();
    const branchesSnap = await bizRef.collection("branches").get();

    const branchStatsMap: Record<string, {
      total_scans: number;
      google_reviews_opened: number;
      total_reviews_redirected: number;
      private_issues: number;
      star_counts: Record<string, number>;
      star_distribution: Record<string, number>;
      monthly_stats: Record<string, Record<string, unknown>>;
    }> = {};

    for (const bDoc of branchesSnap.docs) {
      branchStatsMap[bDoc.id] = {
        total_scans: 0,
        google_reviews_opened: 0,
        total_reviews_redirected: 0,
        private_issues: 0,
        star_counts: {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
        star_distribution: {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
        monthly_stats: {},
      };
    }

    let bizTotalScans = 0;
    let bizGoogleReviews = 0;
    let bizPrivateIssues = 0;
    const bizStarCounts: Record<string, number> = {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0};
    const bizMonthlyStats: Record<string, Record<string, unknown>> = {};

    for (const scanDoc of scansSnap.docs) {
      const d = scanDoc.data();
      const branchId = d.branch_id as string | undefined;
      const starRating = typeof d.star_rating === "number" && d.star_rating >= 1 && d.star_rating <= 5 ? String(d.star_rating) : undefined;
      const actionTaken = d.action_taken as string | undefined;
      const ts = (d.timestamp as FirebaseFirestore.Timestamp | undefined)?.toDate() || new Date();
      const monthKey = `${ts.getFullYear()}-${String(ts.getMonth() + 1).padStart(2, "0")}`;

      bizTotalScans++;
      if (actionTaken === "google_maps") {
        bizGoogleReviews++;
      } else if (actionTaken === "whatsapp" || actionTaken === "feedback_submitted" || actionTaken === "low_skip") {
        bizPrivateIssues++;
      }
      if (starRating) {
        bizStarCounts[starRating] = (bizStarCounts[starRating] || 0) + 1;
      }
      if (!bizMonthlyStats[monthKey]) {
        bizMonthlyStats[monthKey] = {
          total_scans: 0,
          google_reviews_opened: 0,
          total_reviews_redirected: 0,
          private_issues: 0,
          star_counts: {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
          star_distribution: {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
        };
      }
      (bizMonthlyStats[monthKey].total_scans as number)++;
      if (actionTaken === "google_maps") {
        (bizMonthlyStats[monthKey].google_reviews_opened as number)++;
        (bizMonthlyStats[monthKey].total_reviews_redirected as number)++;
      } else if (actionTaken === "whatsapp" || actionTaken === "feedback_submitted" || actionTaken === "low_skip") {
        (bizMonthlyStats[monthKey].private_issues as number)++;
      }
      if (starRating) {
        const starCounts = bizMonthlyStats[monthKey].star_counts as Record<string, number>;
        const starDist = bizMonthlyStats[monthKey].star_distribution as Record<string, number>;
        starCounts[starRating] = (starCounts[starRating] || 0) + 1;
        starDist[starRating] = (starDist[starRating] || 0) + 1;
      }

      if (branchId && branchStatsMap[branchId]) {
        const b = branchStatsMap[branchId];
        b.total_scans++;
        if (actionTaken === "google_maps") {
          b.google_reviews_opened++;
          b.total_reviews_redirected++;
        } else if (actionTaken === "whatsapp" || actionTaken === "feedback_submitted" || actionTaken === "low_skip") {
          b.private_issues++;
        }
        if (starRating) {
          b.star_counts[starRating] = (b.star_counts[starRating] || 0) + 1;
          b.star_distribution[starRating] = (b.star_distribution[starRating] || 0) + 1;
        }
        if (!b.monthly_stats[monthKey]) {
          b.monthly_stats[monthKey] = {
            total_scans: 0,
            google_reviews_opened: 0,
            total_reviews_redirected: 0,
            private_issues: 0,
            star_counts: {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
            star_distribution: {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
          };
        }
        (b.monthly_stats[monthKey].total_scans as number)++;
        if (actionTaken === "google_maps") {
          (b.monthly_stats[monthKey].google_reviews_opened as number)++;
          (b.monthly_stats[monthKey].total_reviews_redirected as number)++;
        } else if (actionTaken === "whatsapp" || actionTaken === "feedback_submitted" || actionTaken === "low_skip") {
          (b.monthly_stats[monthKey].private_issues as number)++;
        }
        if (starRating) {
          const starCounts = b.monthly_stats[monthKey].star_counts as Record<string, number>;
          const starDist = b.monthly_stats[monthKey].star_distribution as Record<string, number>;
          starCounts[starRating] = (starCounts[starRating] || 0) + 1;
          starDist[starRating] = (starDist[starRating] || 0) + 1;
        }
      }
    }

    let activeBranchCount = 0;
    let totalBranchSetupPaid = 0;
    for (const bDoc of branchesSnap.docs) {
      const bData = bDoc.data();
      if (bData.subscription_status === "active") {
        activeBranchCount++;
        totalBranchSetupPaid += (bData.setup_fee_paid as number) || (bData.amount_paid as number) || 1999;
      }
    }

    const bizUpdatePayload: Record<string, unknown> = {
      stats_summary: {
        total_scans: bizTotalScans,
        google_reviews_opened: bizGoogleReviews,
        total_reviews_redirected: bizGoogleReviews,
        private_issues: bizPrivateIssues,
        star_counts: bizStarCounts,
        star_distribution: bizStarCounts,
      },
      monthly_stats: bizMonthlyStats,
      active_branches_count: activeBranchCount,
      total_branches_count: branchesSnap.size,
    };

    const currentBizStatus = bizSnap.data()?.subscription_status;
    if (currentBizStatus === "active" && activeBranchCount > 0) {
      bizUpdatePayload.setup_fee_paid = totalBranchSetupPaid;
      bizUpdatePayload.amount_paid = totalBranchSetupPaid;
    }

    const batch = db.batch();
    batch.update(bizRef, bizUpdatePayload);

    for (const bDoc of branchesSnap.docs) {
      const b = branchStatsMap[bDoc.id];
      if (b) {
        batch.update(bDoc.ref, {
          stats_summary: {
            total_scans: b.total_scans,
            google_reviews_opened: b.google_reviews_opened,
            total_reviews_redirected: b.total_reviews_redirected,
            private_issues: b.private_issues,
            star_counts: b.star_counts,
            star_distribution: b.star_distribution,
          },
          monthly_stats: b.monthly_stats,
        });
      }
    }

    await batch.commit();
    logger.info("reconcileBusinessStats: stats successfully reconciled", {
      businessId,
      totalScans: bizTotalScans,
    });

    return {success: true, businessId, totalScans: bizTotalScans};
  }
);
