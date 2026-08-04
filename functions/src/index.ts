/**
 * Cloud Functions entry point.
 *
 * Functions exported from this file are deployed to Firebase.
 *
 * ─── Place ID / Google Places ────────────────────────────────────────────────
 *   searchPlaces    (callable) — returns 2-3 candidate matches for a business
 *                                name + city search. Requires Auth.
 *   getPlacePhoto   (HTTPS)    — server-side proxy that streams a Places photo
 *                                to authenticated clients. API key stays on the
 *                                server; never forwarded to the browser.
 *
 * ─── QR & NFC ────────────────────────────────────────────────────────────────
 *   onBranchCreated  (Firestore trigger) — fires automatically when a branch
 *                                          doc is created; generates branded QR
 *                                          PNG and writes qr_code_id + nfc_url.
 *   generateBranchQr (callable) — manual re-generation for admin/employee.
 *                                  Requires Auth.
 *
 * ─── Payment, Subscription & Renewal ──────────────────────────────────────
 * (see docs/05-payment-subscription-renewal.md)
 *   createOrder        (callable) — Creates a Razorpay order for the ₹1999
 *                                   one-time setup fee at enrollment time.
 *                                   Requires Auth.
 *   createSubscription (callable) — Creates a Razorpay subscription against
 *                                   the ₹999/year Plan for annual renewal.
 *                                   Requires Auth.
 *   razorpayWebhook    (HTTPS)    — Receives Razorpay webhook events. Verifies
 *                                   HMAC-SHA256 signature before processing.
 *                                   On success: updates subscription_status,
 *                                   renewal_date, creates commission_records.
 *                                   Webhook URL (post-deploy — see razorpay.ts
 *                                   header comment for exact URL).
 *   renewalLifecycle   (scheduled) — Daily: active → grace_period → deleted.
 *                                    Never deletes commission_records.
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
  createSubscription,
  razorpayWebhook,
  renewalLifecycle,
} from "./razorpay.js";
