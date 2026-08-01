/**
 * qrGenerator.ts
 *
 * Cloud Function: generateBranchQr  (callable)
 *
 * Given a branchId, this function:
 *  1. Reads the branch and parent business from Firestore.
 *  2. Builds the review URL: https://{REVIEW_DOMAIN}/r/{branchId}
 *  3. Generates a QR code PNG (error correction H — tolerates logo overlay).
 *  4. Fetches the business logo from Storage or a public URL.
 *  5. Composites the logo (circular, centred) on top of the QR.
 *  6. Applies a category-themed coloured border strip.
 *  7. Resizes to 1200×1800 px (4×6 inches @ 300 dpi) — print-ready.
 *  8. Uploads to Firebase Storage at qr_codes/{branchId}.png.
 *  9. Updates branches/{branchId} in Firestore:
 *       - qr_code_id  = "qr_codes/{branchId}.png"
 *       - nfc_url     = reviewUrl (for manual NFC programming via phone app)
 * 10. Returns { qrStoragePath, nfcUrl, downloadUrl } to the caller.
 *     downloadUrl is a 1-hour signed URL for immediate preview/download.
 *
 * Auth: requires Firebase Auth (employee or admin).
 * Resources: 512 MiB RAM (sharp is memory-intensive), 120 s timeout.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import * as QRCode from "qrcode";
import sharp from "sharp";
import {reviewDomain} from "./secrets.js";

// ---------------------------------------------------------------------------
// Category → border accent colour palette
// Colours are applied as a solid strip around the QR image.
// Replace the extend/flatten step with a PNG overlay for custom artwork.
// ---------------------------------------------------------------------------
const CATEGORY_COLOURS: Record<string, string> = {
  "ice_cream": "#FF6B9D",
  "salon": "#9B59B6",
  "restaurant": "#E67E22",
  "cafe": "#8B4513",
  "pharmacy": "#27AE60",
  "gym": "#E74C3C",
  "spa": "#F39C12",
  "retail": "#2980B9",
};
const DEFAULT_COLOUR = "#3498DB";

/**
 * Pick a border colour keyed to a category name (slugified).
 * @param {string | undefined} categoryType - Business category type string.
 * @return {string} Hex colour code.
 */
function borderColour(categoryType: string | undefined): string {
  if (!categoryType) return DEFAULT_COLOUR;
  const slug = categoryType.toLowerCase().replace(/\s+/g, "_");
  return CATEGORY_COLOURS[slug] ?? DEFAULT_COLOUR;
}

/**
 * Convert a hex colour string to an RGB object for sharp.
 * @param {string} hex - Hex colour e.g. "#FF6B9D".
 * @return {{ r: number, g: number, b: number }} RGB components.
 */
function hexToRgb(hex: string): {r: number; g: number; b: number} {
  const h = hex.replace("#", "");
  return {
    r: parseInt(h.substring(0, 2), 16),
    g: parseInt(h.substring(2, 4), 16),
    b: parseInt(h.substring(4, 6), 16),
  };
}

/**
 * Fetch raw image bytes from a gs:// Storage URI or an HTTPS URL.
 * @param {string} url - Source URL (gs:// or https://).
 * @return {Promise<Buffer>} Image bytes.
 */
async function fetchImageBytes(url: string): Promise<Buffer> {
  if (url.startsWith("gs://")) {
    const bucket = url.replace("gs://", "").split("/")[0];
    const objectPath = url.replace(`gs://${bucket}/`, "");
    const [bytes] = await getStorage()
      .bucket(bucket)
      .file(objectPath)
      .download();
    return bytes;
  }
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Failed to fetch image: HTTP ${res.status}`);
  }
  return Buffer.from(await res.arrayBuffer());
}

/**
 * Build an SVG circular mask buffer for sharp composite.
 * @param {number} size - Diameter in pixels.
 * @return {Buffer} SVG buffer.
 */
function circularMask(size: number): Buffer {
  return Buffer.from(
    `<svg width="${size}" height="${size}">` +
    `<circle cx="${size / 2}" cy="${size / 2}"` +
    ` r="${size / 2}" fill="white"/>` +
    "</svg>"
  );
}

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
// generateBranchQr
// ---------------------------------------------------------------------------

export const generateBranchQr = onCall(
  {
    memory: "512MiB",
    timeoutSeconds: 120,
    maxInstances: 5,
  },
  async (request) => {
    requireAuth(request.auth);

    const {branchId} = request.data as {branchId?: unknown};
    if (typeof branchId !== "string" || branchId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`branchId` must be a non-empty string."
      );
    }

    const db = getFirestore();

    // -- 1. Read branch document via collectionGroup --
    // Branches live at: businesses/{businessId}/branches/{branchId}
    // collectionGroup lets us find the branch without knowing the business ID.
    const branchSnap = await db
      .collectionGroup("branches")
      .where("__name__", "==", branchId)
      .limit(1)
      .get()
      .catch(() => null);

    let branchDoc: FirebaseFirestore.DocumentSnapshot | null = null;
    let businessId = "";

    if (branchSnap && !branchSnap.empty) {
      branchDoc = branchSnap.docs[0];
      businessId = branchDoc.ref.parent.parent?.id ?? "";
    } else {
      throw new HttpsError(
        "not-found",
        `Branch '${branchId}' not found. ` +
        "Make sure you pass the branch document ID."
      );
    }

    // -- 2. Read parent business document --
    if (!businessId) {
      throw new HttpsError(
        "internal",
        "Could not determine parent business ID."
      );
    }
    const businessSnap = await db.doc(`businesses/${businessId}`).get();
    if (!businessSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Business '${businessId}' not found.`
      );
    }
    const businessData = businessSnap.data() ?? {};

    // -- 3. Determine category type for border colour --
    // category_type is on the business doc (see 00-architecture-and-schema.md)
    const categoryType =
      (businessData["category_type"] as string | undefined) ?? "";
    const accent = borderColour(categoryType);
    const {r, g, b} = hexToRgb(accent);

    // -- 4. Build review URL --
    const reviewUrl =
      `https://${reviewDomain.value()}/r/${branchId}`;

    logger.info("generateBranchQr: building QR", {
      branchId,
      businessId,
      reviewUrl,
      categoryType,
      accent,
    });

    // -- 5. Generate QR code PNG buffer --
    // errorCorrectionLevel H (30% damage tolerance) so the logo overlay
    // (~15-20% of QR area) doesn't break decodability.
    const QR_SIZE = 500;
    const qrBuffer: Buffer = await QRCode.toBuffer(reviewUrl, {
      errorCorrectionLevel: "H",
      type: "png",
      margin: 2,
      width: QR_SIZE,
      color: {dark: "#000000", light: "#FFFFFF"},
    });

    // -- 6. Prepare logo overlay (non-fatal if logo unavailable) --
    const LOGO_SIZE = 100;
    let logoComposite: sharp.OverlayOptions[] = [];

    const logoUrl =
      (businessData["logo_url"] as string | undefined) ?? "";
    if (logoUrl) {
      try {
        const rawLogo = await fetchImageBytes(logoUrl);
        const mask = circularMask(LOGO_SIZE);

        // Resize logo, apply circular clip
        const logoCircle = await sharp(rawLogo)
          .resize(LOGO_SIZE, LOGO_SIZE, {fit: "cover"})
          .composite([{input: mask, blend: "dest-in"}])
          .png()
          .toBuffer();

        // White ring around the logo so it stands out on the QR
        const RING = 8;
        const ringSize = LOGO_SIZE + RING * 2;
        const logoWithRing = await sharp({
          create: {
            width: ringSize,
            height: ringSize,
            channels: 4,
            background: {r: 255, g: 255, b: 255, alpha: 1},
          },
        })
          .composite([{input: logoCircle, top: RING, left: RING}])
          .png()
          .toBuffer();

        const offset = Math.floor((QR_SIZE - ringSize) / 2);
        logoComposite = [{input: logoWithRing, top: offset, left: offset}];
      } catch (err) {
        // Logo failures are non-fatal — QR works without the overlay
        logger.warn("generateBranchQr: logo processing failed", {err});
      }
    }

    // -- 7. Composite logo onto QR --
    const qrWithLogo = await sharp(qrBuffer)
      .composite(logoComposite)
      .png()
      .toBuffer();

    // -- 8. Apply category border and resize to print dimensions --
    // Border: 40 px solid accent strip on all sides.
    // Final canvas: 1200×1800 px (4×6 inches @ 300 dpi).
    const BORDER = 40;
    const PRINT_W = 1200;
    const PRINT_H = 1800;

    const qrFinal = await sharp(qrWithLogo)
      .extend({
        top: BORDER,
        bottom: BORDER,
        left: BORDER,
        right: BORDER,
        background: {r, g, b, alpha: 1},
      })
      .resize(Math.min(PRINT_W, PRINT_H), Math.min(PRINT_W, PRINT_H), {
        fit: "inside",
      })
      .png()
      .toBuffer();

    // Centre QR on a white 4×6 canvas
    const {width: qrW, height: qrH} = await sharp(qrFinal).metadata();
    const centreLeft = Math.floor((PRINT_W - (qrW ?? 0)) / 2);
    const centreTop = Math.floor((PRINT_H - (qrH ?? 0)) / 2);

    const printReady = await sharp({
      create: {
        width: PRINT_W,
        height: PRINT_H,
        channels: 4,
        background: {r: 255, g: 255, b: 255, alpha: 1},
      },
    })
      .composite([{input: qrFinal, top: centreTop, left: centreLeft}])
      .png()
      .toBuffer();

    // -- 9. Upload to Firebase Storage --
    const storagePath = `qr_codes/${branchId}.png`;
    const storageBucket = getStorage().bucket();
    const file = storageBucket.file(storagePath);

    await file.save(printReady, {
      metadata: {
        contentType: "image/png",
        metadata: {
          branchId,
          businessId,
          reviewUrl,
          generatedAt: new Date().toISOString(),
        },
      },
    });

    // -- 10. Update Firestore branch document --
    await branchDoc.ref.update({
      qr_code_id: storagePath,
      nfc_url: reviewUrl,
    });

    // -- 11. Return a 1-hour signed URL for immediate preview/download --
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 1);
    const [downloadUrl] = await file.getSignedUrl({
      action: "read",
      expires: expiresAt,
    });

    logger.info("generateBranchQr: complete", {branchId, storagePath});

    return {
      qrStoragePath: storagePath,
      nfcUrl: reviewUrl,
      downloadUrl,
    };
  }
);
