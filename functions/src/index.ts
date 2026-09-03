/**
 * Cloud Functions entry point.
 *
 * Functions exported from this file are deployed to Firebase.
 *
 * ─── Place ID / Google Places ──────────────────────────────────────
 *   searchPlaces    (callable) — 2–3 candidate matches for a business
 *                                name + city search. Requires Auth.
 *   getPlacePhoto   (HTTPS)    — server-side proxy that streams a Places
 *                                photo. API key stays on server.
 *
 * ─── QR & NFC ─────────────────────────────────────────────────────
 *   onBranchCreated  (Firestore trigger) — fires automatically when a
 *                    branch doc is created; generates branded QR PNG
 *                    and writes qr_code_id + nfc_url.
 *   generateBranchQr (callable) — manual re-generation for admin/
 *                    employee. Requires Auth.
 *
 * ─── Payment, Subscription & Renewal ──────────────────────────
 * (see docs/05-payment-subscription-renewal.md)
 *   createOrder        (callable) — Razorpay order for the ₹1999 setup
 *                                   fee. Requires Auth.
 *   createSubscription (callable) — Razorpay subscription for ₹999/yr.
 *                                   Requires Auth.
 *   razorpayWebhook    (HTTPS)    — Receives Razorpay webhook events.
 *                                   HMAC-SHA256 verified. Updates
 *                                   subscription_status, renewal_date,
 *                                   creates commission_records.
 *   renewalLifecycle   (scheduled) — Daily: active → grace_period →
 *                                    deleted. Never deletes
 *                                    commission_records.
 *   cleanupAbandonedDrafts (scheduled) — Daily cleanup of old drafts.
 *   resendPaymentLink  (callable) — Resends payment link to draft owner.
 *   provisionOwner     (callable) — Provisions owner Firebase Auth account.
 *
 * ─── Notifications (doc 08) ──────────────────────────────────────
 * (see docs/08-notifications-system.md)
 *   sendRenewalReminders     (scheduled daily) — emails owner + employee
 *                            at 30/15/7/1 days before renewal_date.
 *                            Writes to notifications/{id}.
 *   sendAdminDigest          (scheduled weekly Mon 09:00 IST) — one
 *                            summary email to admin of upcoming renewals.
 *   sendCashPaymentVerification (callable) — doc 06 fraud prevention;
 *                            "Did you pay ₹X in cash to [Employee]?"
 *                            Reuses same email + notifications infra.
 *
 * ─── Commission Tracking (doc 06) ────────────────────────────────
 * (see docs/06-commission-tracking.md)
 *   confirmCashPaymentOwner (callable) — Owner confirms/disputes cash payment.
 *   confirmCashPaymentAdmin (callable) — Admin approves physical cash receipt.
 *   markCommissionPaidAdmin (callable) — Admin marks verified record as paid.
 */

import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

// Initialise Firebase Admin SDK once, at the module level.
admin.initializeApp();

// Global defaults — can be overridden per-function.
setGlobalOptions({maxInstances: 10, region: "asia-south1"});

// ─── Exports ─────────────────────────────────────────────────────────────────

export {searchPlaces, getPlacePhoto} from "./placeSearch.js";
export {onBranchCreated, generateBranchQr} from "./qrGenerator.js";
export {
  createOrder,
  createBranchOrder,
  createSubscription,
  razorpayWebhook,
  renewalLifecycle,
  cleanupAbandonedDrafts,
  resendPaymentLink,
  resendBranchPaymentLink,
  provisionOwner,
  deleteBusinessAdmin,
} from "./razorpay.js";
export {
  sendRenewalReminders,
  sendAdminDigest,
  sendCashPaymentVerification,
  sendCustomPasswordResetEmail,
} from "./notifications.js";
export {
  confirmCashPaymentAdmin,
  adminCashActivateBranch,
  adminRevertBusinessActivation,
  adminRevertBranchActivation,
  onBusinessActivated,
  onBranchActivated,
  markCommissionsPaidBulk,
} from "./commissions.js";
export {
  createEmployeeAccount,
  offboardEmployee,
  verifyEmployeeDocumentsAdmin,
} from "./employees.js";
export {onScanCreated} from "./scans.js";
