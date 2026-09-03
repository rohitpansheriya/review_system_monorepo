/**
 * qrGenerator.ts
 *
 * Exports Cloud Functions:
 *
 *  onBranchCreated (Firestore trigger)
 *    Fires automatically when a document is created at
 *    businesses/{businessId}/branches/{branchId}.
 *    Generates:
 *      (a) Branded "standee" QR PNG (logo + category border, 4×6 print-ready)
 *          → writes qr_code_id + nfc_url.  [STUB: acrylic standee artwork pipeline, doc 09]
 *      (b) Plain printable QR PNG (simple URL→PNG, 600×600 px, no artwork)
 *          → writes plain_qr_storage_path.  [Change 1 — instant digital deliverable]
 *    Both are skipped for pending_payment (draft) branches.
 *
 *  generateBranchQr (callable)
 *    Manual re-generation — also produces both QR types.
 *    Requires Firebase Auth.
 *
 * buildQrForBranch (exported function)
 *  Full branded standee pipeline (logo + border + 4×6 canvas). See steps below.
 *  Called by: onBranchCreated, generateBranchQr, razorpay.ts activation webhook.
 *
 * buildPlainQrForBranch (exported function — Change 1)
 *  Minimal URL→PNG pipeline: no logo, no border, no resize.
 *  Output: 600×600 px PNG at qr_codes/{branchId}_plain.png.
 *  Called by: onBranchCreated, generateBranchQr, razorpay.ts activation webhook.
 *
 * Resources: 512 MiB RAM (sharp is memory-intensive), 120 s timeout.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import * as QRCode from "qrcode";
import sharp from "sharp";
import {reviewDomain} from "./secrets.js";

// ---------------------------------------------------------------------------
// Category → border accent colour palette
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
 * Returns the border accent colour for a given category type slug.
 * Falls back to DEFAULT_COLOUR if the category is unrecognised.
 * @param {string | undefined} categoryType - The business category string.
 * @return {string} A hex colour code.
 */
function borderColour(categoryType: string | undefined): string {
  if (!categoryType) return DEFAULT_COLOUR;
  const slug = categoryType.toLowerCase().replace(/\s+/g, "_");
  return CATEGORY_COLOURS[slug] ?? DEFAULT_COLOUR;
}

/**
 * Converts a hex colour string to an RGB component object for sharp.
 * @param {string} hex - Hex colour e.g. "#FF6B9D".
 * @return {object} Object with r, g, b number fields (0-255 each).
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
 * Fetches raw image bytes from a gs:// Storage URI or an HTTPS URL.
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
 * Builds an SVG circular mask buffer for sharp composite operations.
 * @param {number} size - Diameter in pixels.
 * @return {Buffer} SVG buffer containing a white circle.
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
 * Throws HttpsError("unauthenticated") if the caller has no Firebase Auth uid.
 * @param {{ uid: string } | undefined} auth - Auth context from onCall request.
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
// buildQrForBranch — shared standee image pipeline
// ---------------------------------------------------------------------------

interface QrResult {
  qrStoragePath: string;
  nfcUrl: string;
}

/** Result of buildPlainQrForBranch — Change 1. */
interface PlainQrResult {
  plainQrStoragePath: string;
  plainQrUrl: string;
}

/**
 * Runs the full QR image pipeline for a branch:
 * reads business data, generates a branded QR PNG, uploads to Storage,
 * and writes qr_code_id + nfc_url back to the branch Firestore document.
 *
 * Exported so the payment webhook (razorpay.ts) can call it directly
 * during draft activation without going through the Firestore trigger.
 *
 * @param {string} businessId - Firestore document ID of the parent business.
 * @param {string} branchId - Firestore document ID of the branch.
 * @param {FirebaseFirestore.DocumentReference} branchRef - Live ref to branch.
 * @return {Promise<QrResult>} Storage path and review URL.
 */
export async function buildQrForBranch(

  businessId: string,
  branchId: string,
  branchRef: FirebaseFirestore.DocumentReference
): Promise<QrResult> {
  const db = getFirestore();

  // -- 1. Read parent business --
  const businessSnap = await db.doc(`businesses/${businessId}`).get();
  if (!businessSnap.exists) {
    throw new Error(`Business '${businessId}' not found.`);
  }
  const businessData = businessSnap.data() ?? {};

  // -- 2. Build review URL --
  // Two-segment URL: /r/{businessId}/{branchId}
  // The consumer page needs both IDs to look up the subcollection without
  // a collectionGroup query (which would require list permission).
  const domain = reviewDomain.value();
  const reviewUrl = `https://${domain}/r/${businessId}/${branchId}`;

  // -- 3. Category border colour --
  const categoryType =
    (businessData["category_type"] as string | undefined) ?? "";
  const accent = borderColour(categoryType);
  const {r, g, b} = hexToRgb(accent);

  logger.info("buildQrForBranch: building QR", {
    branchId, businessId, reviewUrl, categoryType, accent,
  });

  // -- 4. Generate QR code PNG --
  const QR_SIZE = 500;
  const qrBuffer: Buffer = await QRCode.toBuffer(reviewUrl, {
    errorCorrectionLevel: "H",
    type: "png",
    margin: 2,
    width: QR_SIZE,
    color: {dark: "#000000", light: "#FFFFFF"},
  });

  // -- 5. Logo overlay (non-fatal if logo unavailable) --
  const LOGO_SIZE = 100;
  let logoComposite: sharp.OverlayOptions[] = [];
  const logoUrl = (businessData["logo_url"] as string | undefined) ?? "";

  if (logoUrl) {
    try {
      const rawLogo = await fetchImageBytes(logoUrl);
      const mask = circularMask(LOGO_SIZE);
      const logoCircle = await sharp(rawLogo)
        .resize(LOGO_SIZE, LOGO_SIZE, {fit: "cover"})
        .composite([{input: mask, blend: "dest-in"}])
        .png()
        .toBuffer();

      const RING = 8;
      const ringSize = LOGO_SIZE + RING * 2;
      const logoWithRing = await sharp({
        create: {
          width: ringSize, height: ringSize,
          channels: 4, background: {r: 255, g: 255, b: 255, alpha: 1},
        },
      })
        .composite([{input: logoCircle, top: RING, left: RING}])
        .png()
        .toBuffer();

      const offset = Math.floor((QR_SIZE - ringSize) / 2);
      logoComposite = [{input: logoWithRing, top: offset, left: offset}];
    } catch (err) {
      // Logo failures are non-fatal — QR works fine without the overlay.
      logger.warn("buildQrForBranch: logo processing failed", {err});
    }
  }

  // -- 6. Composite logo onto QR --
  const qrWithLogo = await sharp(qrBuffer)
    .composite(logoComposite)
    .png()
    .toBuffer();

  // -- 7. Border + resize to print dimensions --
  const BORDER = 40;
  const PRINT_W = 1200;
  const PRINT_H = 1800;
  const TARGET_QR_SIZE = 1000;

  const qrResized = await sharp(qrWithLogo)
    .resize(TARGET_QR_SIZE - BORDER * 2, TARGET_QR_SIZE - BORDER * 2, {
      fit: "inside",
    })
    .png()
    .toBuffer();

  const qrFinal = await sharp(qrResized)
    .extend({
      top: BORDER, bottom: BORDER, left: BORDER, right: BORDER,
      background: {r, g, b, alpha: 1},
    })
    .png()
    .toBuffer();

  const meta = await sharp(qrFinal).metadata();
  const qrW = meta.width ?? 0;
  const qrH = meta.height ?? 0;
  const centreLeft = Math.floor((PRINT_W - qrW) / 2);
  const centreTop = Math.floor((PRINT_H - qrH) / 2);

  const printReady = await sharp({
    create: {
      width: PRINT_W, height: PRINT_H,
      channels: 4, background: {r: 255, g: 255, b: 255, alpha: 1},
    },
  })
    .composite([{input: qrFinal, top: centreTop, left: centreLeft}])
    .png()
    .toBuffer();

  // -- 8. Upload to Firebase Storage --
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

  // -- 9. Write qr_code_id + nfc_url back to the branch doc --
  await branchRef.update({
    qr_code_id: storagePath,
    nfc_url: reviewUrl,
  });

  logger.info("buildQrForBranch: complete", {branchId, storagePath, reviewUrl});
  return {qrStoragePath: storagePath, nfcUrl: reviewUrl};
}

// ---------------------------------------------------------------------------
// buildPlainQrForBranch — plain printable QR (Change 1)
// ---------------------------------------------------------------------------

/**
 * Generates a plain printable QR PNG for a branch:
 *   - No logo overlay, no border, no print canvas.
 *   - 600×600 px — enough for a desktop printer at normal quality.
 *   - Error correction H for readability.
 *   - Encodes the same review URL as the standee QR.
 *   - Uploaded to Firebase Storage at qr_codes/{branchId}_plain.png.
 *   - Writes plain_qr_storage_path back to the branch doc.
 *
 * This is the instant digital deliverable (Change 1).
 * Separate from the acrylic standee artwork (buildQrForBranch / doc 09 stub).
 *
 * @param {string} businessId - Firestore document ID of the parent business.
 * @param {string} branchId - Firestore document ID of the branch.
 * @param {FirebaseFirestore.DocumentReference} branchRef - Live ref to branch.
 * @return {Promise<PlainQrResult>} Storage path and review URL.
 */
export async function buildPlainQrForBranch(
  businessId: string,
  branchId: string,
  branchRef: FirebaseFirestore.DocumentReference
): Promise<PlainQrResult> {
  const domain = reviewDomain.value();
  const plainQrUrl = `https://${domain}/r/${businessId}/${branchId}`;

  logger.info("buildPlainQrForBranch: generating plain QR", {
    branchId, businessId, plainQrUrl,
  });

  // Generate minimal QR — URL → PNG, error correction H, 600×600 px.
  // No logo overlay, no category border, no canvas padding.
  const PLAIN_SIZE = 600;
  const plainQrBuffer: Buffer = await QRCode.toBuffer(plainQrUrl, {
    errorCorrectionLevel: "H",
    type: "png",
    margin: 2,
    width: PLAIN_SIZE,
    color: {dark: "#000000", light: "#FFFFFF"},
  });

  // Upload to Firebase Storage.
  const storagePath = `qr_codes/${branchId}_plain.png`;
  const storageBucket = getStorage().bucket();
  const file = storageBucket.file(storagePath);

  await file.save(plainQrBuffer, {
    metadata: {
      contentType: "image/png",
      metadata: {
        branchId,
        businessId,
        reviewUrl: plainQrUrl,
        type: "plain_printable",
        generatedAt: new Date().toISOString(),
      },
    },
  });

  // Write plain_qr_storage_path back to the branch doc.
  await branchRef.update({
    plain_qr_storage_path: storagePath,
  });

  logger.info("buildPlainQrForBranch: complete", {branchId, storagePath, plainQrUrl});
  return {plainQrStoragePath: storagePath, plainQrUrl};
}

// ---------------------------------------------------------------------------
// onBranchCreated — Firestore trigger
// Fires when a new branch document is created under any business.
// ---------------------------------------------------------------------------
export const onBranchCreated = onDocumentCreated(
  {
    document: "businesses/{businessId}/branches/{branchId}",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const {businessId, branchId} = event.params;

    // Skip if this branch already has a QR (e.g. manually set during import)
    const data = event.data?.data();
    if (data?.qr_code_id) {
      logger.info("onBranchCreated: qr_code_id already set — skipping", {
        branchId,
      });
      return;
    }

    // DRAFT GUARD: Do NOT generate a QR for a pending_payment (draft) business.
    // QR generation is deferred until the payment webhook confirms payment and
    // activates the business (activateDraft in razorpay.ts).
    const db = getFirestore();
    const bizSnap = await db.doc(`businesses/${businessId}`).get();
    const bizStatus = bizSnap.data()?.subscription_status as string | undefined;

    if (bizStatus === "pending_payment") {
      logger.info(
        "onBranchCreated: parent business is a draft (pending_payment) — " +
        "skipping QR generation. Will be triggered by the payment webhook.",
        {businessId, branchId}
      );
      return;
    }

    logger.info("onBranchCreated: new branch, generating QR", {
      businessId, branchId,
    });

    if (!event.data) {
      logger.warn("onBranchCreated: event.data is null, cannot proceed");
      return;
    }

    // Generate branded standee QR (doc 09 pipeline).
    try {
      const result = await buildQrForBranch(
        businessId,
        branchId,
        event.data.ref
      );
      logger.info("onBranchCreated: standee QR ready", result);
    } catch (err) {
      logger.error("onBranchCreated: standee QR generation failed", {
        err, businessId, branchId,
      });
      // Non-fatal — branch doc is still valid without a QR.
    }

    // Change 1: Also generate plain printable QR (instant digital deliverable).
    try {
      const plainResult = await buildPlainQrForBranch(
        businessId,
        branchId,
        event.data.ref
      );
      logger.info("onBranchCreated: plain QR ready", plainResult);
    } catch (err) {
      logger.error("onBranchCreated: plain QR generation failed", {
        err, businessId, branchId,
      });
      // Non-fatal.
    }
  }
);


// ---------------------------------------------------------------------------
// generateBranchQr — callable (admin/employee manual re-generation)
// ---------------------------------------------------------------------------
export const generateBranchQr = onCall(
  {memory: "512MiB", timeoutSeconds: 120, maxInstances: 5},
  async (request) => {
    requireAuth(request.auth);

    const {businessId, branchId} =
      request.data as {businessId?: unknown; branchId?: unknown};

    if (typeof businessId !== "string" || businessId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`businessId` must be a non-empty string."
      );
    }
    if (typeof branchId !== "string" || branchId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "`branchId` must be a non-empty string."
      );
    }

    const db = getFirestore();
    const branchRef =
      db.doc(`businesses/${businessId}/branches/${branchId}`);
    const branchSnap = await branchRef.get();

    if (!branchSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Branch '${branchId}' not found under business '${businessId}'.`
      );
    }

    // DRAFT GUARD & AUTHORIZATION: refuse QR generation for unauthorized callers or unpaid businesses.
    const bizSnap = await db.doc(`businesses/${businessId}`).get();
    const bizData = bizSnap.data();
    const bizStatus = bizData?.subscription_status as string | undefined;

    const callerRole = request.auth?.token?.role;
    const callerUid = request.auth?.uid;
    const isAuthorized = callerRole === "admin" ||
      bizData?.enrolled_by === callerUid ||
      bizData?.owner_auth_uid === callerUid;

    if (!isAuthorized) {
      throw new HttpsError(
        "permission-denied",
        "You do not have permission to generate QR codes for this business."
      );
    }

    if (bizStatus === "pending_payment") {
      throw new HttpsError(
        "failed-precondition",
        "Cannot generate a QR code for a business that has not yet completed payment. " +
        "The QR will be generated automatically when payment is confirmed."
      );
    }

    // Generate both QR types (standee + plain printable).
    const result = await buildQrForBranch(businessId, branchId, branchRef);

    // Change 1: also generate / regenerate plain printable QR.
    let plainDownloadUrl: string | null = null;
    try {
      const plainResult = await buildPlainQrForBranch(businessId, branchId, branchRef);
      const plainExpiresAt = new Date();
      plainExpiresAt.setHours(plainExpiresAt.getHours() + 1);
      const plainFile = getStorage().bucket().file(plainResult.plainQrStoragePath);
      [plainDownloadUrl] = await plainFile.getSignedUrl({
        action: "read",
        expires: plainExpiresAt,
      });
    } catch (plainErr) {
      logger.warn("generateBranchQr: plain QR generation failed (non-fatal)", {plainErr});
    }

    // Return 1-hour signed URL for standee QR immediate download/preview.
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 1);
    const file = getStorage().bucket().file(result.qrStoragePath);
    const [downloadUrl] = await file.getSignedUrl({
      action: "read",
      expires: expiresAt,
    });

    return {...result, downloadUrl, plainDownloadUrl};
  }
);
