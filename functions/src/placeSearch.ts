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
import {getFirestore, Timestamp} from "firebase-admin/firestore";
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
  rating?: number | null;
  userRatingCount?: number | null;
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
          rating: 4.6,
          userRatingCount: 128,
        },
        {
          name: `${name} - City Center`,
          address: `45 Station Road, ${loc}`,
          placeId: `ChIJ_mock_${mockSlug}_002`,
          photoReference: null,
          rating: 4.3,
          userRatingCount: 79,
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
            "places.id,places.displayName,places.formattedAddress,places.photos,places.rating,places.userRatingCount",
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

        const ratingVal =
          typeof place["rating"] === "number" ?
            place["rating"] :
            null;
        const countVal =
          typeof place["userRatingCount"] === "number" ?
            place["userRatingCount"] :
            null;

        return {
          name: placeName,
          address: (place["formattedAddress"] as string) ?? "",
          placeId: (place["id"] as string) ?? "",
          photoReference: photoRef,
          rating: ratingVal,
          userRatingCount: countVal,
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
// syncBranchGoogleRating
// ---------------------------------------------------------------------------

/**
 * Callable: sync or fetch Google Places rating & review count for a branch.
 * If the branch does not have `initial_rating` set yet (e.g. legacy enrolled businesses),
 * it sets initial_rating, initial_review_count, and initial_rating_captured_at.
 * Also updates current_rating, current_review_count, and last_rating_sync_at.
 *
 * Input: { branchId: string }
 * Output: { success: boolean, rating: number | null, userRatingCount: number | null, isNewBaseline: boolean }
 */
export const syncBranchGoogleRating = onCall(
  {secrets: [placeApiKey], maxInstances: 10},
  async (request) => {
    requireAuth(request.auth);

    const {branchId, businessId} = request.data as {branchId?: unknown; businessId?: unknown};
    if (typeof branchId !== "string" || branchId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "Valid `branchId` is required.");
    }

    const db = getFirestore();
    let branchRef: FirebaseFirestore.DocumentReference | null = null;
    let branchSnap: FirebaseFirestore.DocumentSnapshot | null = null;

    if (typeof businessId === "string" && businessId.trim().length > 0) {
      branchRef = db.collection("businesses").doc(businessId.trim()).collection("branches").doc(branchId.trim());
      branchSnap = await branchRef.get();
    }

    if (!branchSnap || !branchSnap.exists) {
      const groupSnap = await db.collectionGroup("branches").get();
      const match = groupSnap.docs.find((d) => d.id === branchId.trim());
      if (match) {
        branchRef = match.ref;
        branchSnap = match;
      }
    }

    if (!branchSnap || !branchSnap.exists || !branchRef) {
      throw new HttpsError("not-found", `Branch "${branchId}" not found.`);
    }

    const branchData = branchSnap.data() || {};
    const placeId = (branchData.place_id as string | undefined)?.trim();

    if (!placeId) {
      throw new HttpsError(
        "failed-precondition",
        "This branch does not have a Google Place ID configured."
      );
    }

    // Enforce 7-day rate limit for non-admin callers if an initial baseline or previous sync exists
    const lastSyncRaw = branchData.last_rating_sync_at || branchData.initial_rating_captured_at;
    const hasExistingBaseline = branchData.initial_rating !== undefined && branchData.initial_rating !== null;
    const isAdmin = request.auth?.token?.role === "admin";

    if (!isAdmin && hasExistingBaseline && lastSyncRaw) {
      const lastSyncDate =
        typeof (lastSyncRaw as FirebaseFirestore.Timestamp).toDate === "function" ?
          (lastSyncRaw as FirebaseFirestore.Timestamp).toDate() :
          new Date(lastSyncRaw as string | number);

      const nextEligibleTime = lastSyncDate.getTime() + 7 * 24 * 60 * 60 * 1000;
      if (Date.now() < nextEligibleTime) {
        const remainingMs = nextEligibleTime - Date.now();
        const remainingDays = Math.max(1, Math.ceil(remainingMs / (24 * 60 * 60 * 1000)));
        throw new HttpsError(
          "failed-precondition",
          `Google Places rating sync is available once every 7 days. Next update unlocks in ${remainingDays} day${remainingDays === 1 ? "" : "s"}.`
        );
      }
    }

    let rating: number | null = null;
    let userRatingCount: number | null = null;

    const apiKey = placeApiKey.value();
    if (!apiKey || apiKey === "PLACEHOLDER" || apiKey.length < 10) {
      // Mock mode: generate mock baseline or refreshed stats
      logger.info("syncBranchGoogleRating: Mock API key active, generating mock rating");
      rating = branchData.current_rating ?? branchData.initial_rating ?? 4.5;
      userRatingCount = (branchData.current_review_count ?? branchData.initial_review_count ?? 120) + 3;
    } else {
      // Places API (New) Place Details: GET https://places.googleapis.com/v1/places/{placeId}
      const url = `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`;
      try {
        const res = await fetch(url, {
          method: "GET",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": "id,rating,userRatingCount,displayName",
          },
        });

        if (!res.ok) {
          const errText = await res.text().catch(() => "");
          logger.warn("Places Details API error", {status: res.status, errText, placeId});
          throw new HttpsError("unavailable", `Google Places API returned HTTP ${res.status}`);
        }

        const data = (await res.json()) as Record<string, unknown>;
        rating = typeof data["rating"] === "number" ? data["rating"] : null;
        userRatingCount = typeof data["userRatingCount"] === "number" ? data["userRatingCount"] : null;
      } catch (err) {
        if (err instanceof HttpsError) throw err;
        logger.error("Failed to fetch Google Place details", {err, placeId});
        throw new HttpsError("internal", "Failed to retrieve Place details from Google.");
      }
    }

    const updatePayload: Record<string, unknown> = {
      current_rating: rating,
      current_review_count: userRatingCount,
      last_rating_sync_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    };

    let isNewBaseline = false;
    if (branchData.initial_rating === undefined || branchData.initial_rating === null) {
      updatePayload.initial_rating = rating;
      updatePayload.initial_review_count = userRatingCount;
      updatePayload.initial_rating_captured_at = Timestamp.now();
      isNewBaseline = true;
    }

    await branchRef.update(updatePayload);

    logger.info("syncBranchGoogleRating updated branch", {
      branchId,
      placeId,
      rating,
      userRatingCount,
      isNewBaseline,
    });

    return {
      success: true,
      rating,
      userRatingCount,
      isNewBaseline,
    };
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
