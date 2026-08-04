/**
 * secrets.ts
 *
 * Central registry for all Firebase Functions secrets and params.
 * Import from here — never re-declare defineSecret/defineString inline.
 *
 * ─── Secrets (Secret Manager — never readable from client) ──────────────
 *   PLACE_API_KEY           — Google Places API key
 *   RAZORPAY_KEY_ID         — Razorpay API key ID   (test: rzp_test_…)
 *   RAZORPAY_KEY_SECRET     — Razorpay API key secret
 *   RAZORPAY_WEBHOOK_SECRET — Shared secret from Razorpay dashboard
 *                             Settings → Webhooks. Used for HMAC-SHA256
 *                             signature verification of incoming events.
 *
 * ─── Params (plain Functions config — not sensitive) ────────────────────
 *   REVIEW_DOMAIN    — hostname for /r/{branchId} review URL
 *   RAZORPAY_PLAN_ID — Plan ID for the ₹999/year subscription plan.
 *                      Not secret: it is a public plan identifier.
 *                      Set via: firebase functions:params:set \
 *                               RAZORPAY_PLAN_ID=plan_XXXXXXXX
 */

import {defineSecret, defineString} from "firebase-functions/params";

// ─── Google Places ──────────────────────────────────────────────────────────

/** Google Places API key — stored in Secret Manager, never sent to client. */
export const placeApiKey = defineSecret("PLACE_API_KEY");

// ─── Razorpay ───────────────────────────────────────────────────────────────

/**
 * Razorpay API Key ID — public-ish (like a username) but stored as a
 * secret so it is never baked into source control or bundle output.
 * Set via: firebase functions:secrets:set RAZORPAY_KEY_ID
 */
export const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");

/**
 * Razorpay API Key Secret — never expose to any client.
 * Set via: firebase functions:secrets:set RAZORPAY_KEY_SECRET
 */
export const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");

/**
 * Razorpay Webhook Secret — configured when creating a webhook endpoint
 * in Razorpay dashboard → Settings → Webhooks.
 * Used server-side only for HMAC-SHA256 signature verification.
 * Set via: firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
 */
export const razorpayWebhookSecret = defineSecret("RAZORPAY_WEBHOOK_SECRET");

/**
 * Razorpay Plan ID for the ₹999/year subscription plan.
 * NOT a secret — it is a public plan identifier visible in the dashboard.
 * Store as a plain param so it can be changed without a redeploy.
 * Set via: firebase functions:params:set RAZORPAY_PLAN_ID=plan_XXXXXXXX
 */
export const razorpayPlanId = defineString("RAZORPAY_PLAN_ID");

// ─── Domain ─────────────────────────────────────────────────────────────────

/**
 * Domain used to construct review page URLs.
 * Set via: firebase functions:params:set REVIEW_DOMAIN=yourdomain.com
 *
 * Falls back to the Firebase hosting domain until a real domain exists.
 * This is NOT a secret — it is a plain string param.
 */
export const reviewDomain = defineString("REVIEW_DOMAIN", {
  default: "review-system-prod-49b7a.web.app",
});
