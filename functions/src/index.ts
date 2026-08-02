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

