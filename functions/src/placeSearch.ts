/**
 * placeSearch.ts
 *
 * Cloud Functions for Google Places API integration:
 *
 *  searchPlaces   (callable) — takes businessName + city, returns up to 3
 *                              candidate matches for the admin/employee.
 *  getPlacePhoto  (HTTPS)    — server-side photo proxy; API key stays on
 *                              the server and is never sent to the browser.
 *
 * Auth: both functions require Firebase Auth (employee or admin).
 * Secret: PLACE_API_KEY (Google Places API key in Secret Manager).
 */

import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {placeApiKey} from "./secrets.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A single candidate result returned to the caller. */
export interface PlaceCandidate {
  name: string;
  address: string;
  placeId: string;
  /**
   * Opaque token — client must call getPlacePhoto to retrieve the image.
   * The API key is never included in this token or returned to the client.
   */
  photoReference: string | null;
}

// ---------------------------------------------------------------------------
// Helper: validate caller is authenticated
// ---------------------------------------------------------------------------

/**
 * Throws HttpsError(unauthenticated) if the caller has no Firebase Auth uid.
 * @param {object | undefined} auth - The auth context from the onCall request.
 */
function requireAuth(auth: {uid: string} | undefined): void {
  if (!auth?.uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in as an employee or admin."
    );
  }
}

// ---------------------------------------------------------------------------
// searchPlaces
// ---------------------------------------------------------------------------

/**
 * Callable: search Google Places for a business name + city.
 *
 * Input:  { businessName: string, city: string }
 * Output: { candidates: PlaceCandidate[] }  (up to 3 results)
 *
 * Uses Places Text Search which natively returns multiple candidates —
 * unlike Find Place From Text which returns only one.
 */
export const searchPlaces = onCall(
  {secrets: [placeApiKey], maxInstances: 10},
  async (request) => {
    requireAuth(request.auth);

    const {businessName, city} = request.data as {
      businessName?: unknown;
      city?: unknown;
    };

    if (
      typeof businessName !== "string" ||
      businessName.trim().length === 0 ||
      typeof city !== "string" ||
      city.trim().length === 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Both `businessName` and `city` must be non-empty strings."
      );
    }

    const query = encodeURIComponent(
      `${businessName.trim()} ${city.trim()}`
    );
    // Request only the fields we need — billed per field mask.
    const fields = "name,place_id,formatted_address,photos,geometry";
    const url =
      "https://maps.googleapis.com/maps/api/place/textsearch/json" +
      `?query=${query}` +
      `&fields=${fields}` +
      `&key=${placeApiKey.value()}`;

    let json: Record<string, unknown>;
    try {
      const res = await fetch(url);
      if (!res.ok) {
        throw new Error(`Places API HTTP ${res.status}`);
      }
      json = (await res.json()) as Record<string, unknown>;
    } catch (err) {
      logger.error("Places API fetch failed", {err});
      throw new HttpsError(
        "internal",
        "Failed to contact Google Places API. Please try again."
      );
    }

    const status = json["status"];
    if (status !== "OK" && status !== "ZERO_RESULTS") {
      logger.error("Places API returned error status", {status});
      throw new HttpsError(
        "internal",
        `Google Places API error: ${status}`
      );
    }

    const results = (json["results"] as unknown[] | undefined) ?? [];
    const candidates: PlaceCandidate[] = results
      .slice(0, 3)
      .map((r) => {
        const result = r as Record<string, unknown>;
        const photos = result["photos"] as
          | Array<Record<string, unknown>>
          | undefined;
        const photoRef =
          photos && photos.length > 0 ?
            (photos[0]["photo_reference"] as string) :
            null;

        return {
          name: (result["name"] as string) ?? "",
          address: (result["formatted_address"] as string) ?? "",
          placeId: (result["place_id"] as string) ?? "",
          photoReference: photoRef,
        };
      });

    logger.info("searchPlaces returned candidates", {
      query: `${businessName} ${city}`,
      count: candidates.length,
      callerUid: request.auth?.uid,
    });

    return {candidates};
  }
);

// ---------------------------------------------------------------------------
// getPlacePhoto  (HTTPS — streams image bytes, API key stays server-side)
// ---------------------------------------------------------------------------

/**
 * HTTPS function: proxy a Google Places photo to authenticated clients.
 *
 * The client passes a Firebase ID token (Authorization: Bearer <token>).
 * Query params:
 *   photoReference  — opaque token from searchPlaces
 *   maxWidth        — desired pixel width (default 400, max 1600)
 *
 * The PLACE_API_KEY is read from Secret Manager and is never forwarded.
 */
export const getPlacePhoto = onRequest(
  {secrets: [placeApiKey], maxInstances: 10},
  async (req, res) => {
    // -- Auth check via Authorization: Bearer <idToken> header --
    const authHeader = req.headers["authorization"] ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "Missing Authorization header"});
      return;
    }
    const idToken = authHeader.slice(7);
    try {
      const {getAuth} = await import("firebase-admin/auth");
      await getAuth().verifyIdToken(idToken);
    } catch {
      res.status(401).json({error: "Invalid or expired ID token"});
      return;
    }

    const photoReference =
      req.query["photoReference"] as string | undefined;
    if (!photoReference) {
      res.status(400).json({error: "Missing photoReference query param"});
      return;
    }

    const maxWidth = Math.min(
      Number(req.query["maxWidth"] ?? "400"),
      1600
    );

    const photoUrl =
      "https://maps.googleapis.com/maps/api/place/photo" +
      `?maxwidth=${maxWidth}` +
      `&photo_reference=${encodeURIComponent(photoReference)}` +
      `&key=${placeApiKey.value()}`;

    try {
      const upstream = await fetch(photoUrl);
      if (!upstream.ok) {
        throw new Error(`Places photo HTTP ${upstream.status}`);
      }
      const contentType =
        upstream.headers.get("content-type") ?? "image/jpeg";
      res.setHeader("Content-Type", contentType);
      res.setHeader("Cache-Control", "private, max-age=3600");
      const buffer = await upstream.arrayBuffer();
      res.status(200).end(Buffer.from(buffer));
    } catch (err) {
      logger.error("getPlacePhoto upstream fetch failed", {err});
      res.status(502).json({error: "Failed to fetch photo from Google"});
    }
  }
);
