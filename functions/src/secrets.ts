/**
 * secrets.ts
 *
 * Central registry for all Firebase Functions secrets and params.
 * Import from here — never re-declare defineSecret/defineString inline.
 *
 * Secrets (Secret Manager — never readable from client):
 *   PLACE_API_KEY  — Google Places API key
 *
 * Params (plain Functions config — not sensitive):
 *   REVIEW_DOMAIN  — hostname for /r/{branchId} review URL
 */

import {defineSecret, defineString} from "firebase-functions/params";

/** Google Places API key — stored in Secret Manager, never sent to client. */
export const placeApiKey = defineSecret("PLACE_API_KEY");

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
