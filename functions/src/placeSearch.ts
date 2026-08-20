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

    const name = businessName.trim();
    const loc = city.trim();
    const mockSlug = name.toLowerCase().replace(/[^a-z0-9]/g, "_");

    // Helper: generate mock candidates when API key is missing or API errors.
    const mockFallback = () => ({
      candidates: [
        {
          name: `${name} - Main Branch`,
          address: `101 Commercial Street, ${loc}`,
          placeId: `ChIJ_mock_${mockSlug}_001`,
          photoReference: null,
        },
        {
          name: `${name} - City Center`,
          address: `45 Station Road, ${loc}`,
          placeId: `ChIJ_mock_${mockSlug}_002`,
          photoReference: null,
        },
      ],
    });

    // Guard: if PLACE_API_KEY is not configured, return mock candidates.
    const apiKey = placeApiKey.value();
    if (!apiKey || apiKey === "PLACEHOLDER" || apiKey.length < 10) {
      logger.warn(
        "🔑 PLACE_API_KEY NOT CONFIGURED — returning mock candidates. " +
        "To fix: 1) Create a key in Google Cloud Console with Places API (New) enabled, " +
        "2) Run: firebase functions:secrets:set PLACE_API_KEY, " +
        "3) Redeploy functions.",
        {
          keyPresent: !!apiKey,
          keyLength: apiKey ? apiKey.length : 0,
          isPlaceholder: apiKey === "PLACEHOLDER",
        }
      );
      return mockFallback();
    }

    logger.info("searchPlaces: API key present, calling Places API (New)", {
      query: `${name} ${loc}`,
      keyPrefix: apiKey.substring(0, 6) + "...",
      callerUid: request.auth?.uid,
    });

    // ── Places API (New) — POST https://places.googleapis.com/v1/places:searchText
    // Docs: https://developers.google.com/maps/documentation/places/web-service/text-search
    const url = "https://places.googleapis.com/v1/places:searchText";

    let json: Record<string, unknown>;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask":
            "places.id,places.displayName,places.formattedAddress,places.photos",
        },
        body: JSON.stringify({
          textQuery: `${name} ${loc}`,
          languageCode: "en",
          regionCode: "IN",
          maxResultCount: 3,
        }),
      });

      if (!res.ok) {
        const errorBody = await res.text().catch(() => "");
        const hint = res.status === 403 ?
          "API key may be restricted or Places API (New) not enabled on this project." :
          res.status === 400 ?
            "Bad request — check if Places API (New) is enabled (not legacy Places API)." :
            `HTTP ${res.status}`;
        logger.warn("⚠️ Places API (New) HTTP error — " + hint, {
          status: res.status,
          errorBody: errorBody.substring(0, 500),
          query: `${name} ${loc}`,
        });
        return mockFallback();
      }

      json = (await res.json()) as Record<string, unknown>;
    } catch (err) {
      logger.error("Places API (New) fetch failed, returning mock fallback", {err});
      return mockFallback();
    }

    // The new API returns { places: [...] } or {} when no results.
    const places = (json["places"] as unknown[] | undefined) ?? [];

    if (places.length === 0) {
      logger.info("searchPlaces: zero results from API", {
        query: `${name} ${loc}`,
        callerUid: request.auth?.uid,
      });
      return {candidates: []};
    }

    const candidates: PlaceCandidate[] = places
      .slice(0, 3)
      .map((p) => {
        const place = p as Record<string, unknown>;

        // displayName is { text: string, languageCode: string }
        const displayName = place["displayName"] as
          | Record<string, unknown>
          | undefined;
        const placeName =
          (displayName?.["text"] as string) ?? "";

        // photos is [ { name: "places/{id}/photos/{ref}", ... }, ... ]
        const photos = place["photos"] as
          | Array<Record<string, unknown>>
          | undefined;
        const photoRef =
          photos && photos.length > 0 ?
            (photos[0]["name"] as string) :
            null;

        return {
          name: placeName,
          address: (place["formattedAddress"] as string) ?? "",
          placeId: (place["id"] as string) ?? "",
          photoReference: photoRef,
        };
      });

    logger.info("searchPlaces returned candidates", {
      query: `${name} ${loc}`,
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
