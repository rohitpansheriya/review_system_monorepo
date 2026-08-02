"use strict";
/**
 * functions/src/scripts/test-doc-09.ts
 *
 * ─── Dev-only smoke test for doc 09 QR generation ─────────────────────────
 * NOT deployed — excluded from tsc output via the tsconfig "exclude" list.
 *
 * What it does:
 *   1. Creates a dummy business + branch in the Firestore emulator.
 *   2. Runs the same image pipeline as generateBranchQr (no callable wrapper,
 *      no Auth requirement, no Storage upload — saves the PNG to disk instead).
 *   3. Prints the local file path so you can open and visually inspect the QR.
 *
 * Run:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *   REVIEW_DOMAIN=localhost:5002 \
 *   npx ts-node --esm functions/src/scripts/test-doc-09.ts
 *
 * If ts-node isn't available, compile first:
 *   cd functions && npm run build
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 REVIEW_DOMAIN=localhost:5002 \
 *   node lib/scripts/test-doc-09.js
 *
 * Prerequisites: emulator already running:
 *   firebase emulators:start --only firestore,hosting
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
var _a, _b;
Object.defineProperty(exports, "__esModule", { value: true });
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const QRCode = __importStar(require("qrcode"));
const sharp_1 = __importDefault(require("sharp"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
// ─── Config ──────────────────────────────────────────────────────────────────
const PROJECT_ID = (_a = process.env.GCLOUD_PROJECT) !== null && _a !== void 0 ? _a : 'review-system-prod-49b7a';
const REVIEW_DOMAIN = (_b = process.env.REVIEW_DOMAIN) !== null && _b !== void 0 ? _b : 'localhost:5002';
// ─── Admin SDK init ──────────────────────────────────────────────────────────
if ((0, app_1.getApps)().length === 0) {
    (0, app_1.initializeApp)({ projectId: PROJECT_ID });
}
const db = (0, firestore_1.getFirestore)();
db.settings({ ignoreUndefinedProperties: true });
// ─── Category → border colour (mirrors qrGenerator.ts) ──────────────────────
const CATEGORY_COLOURS = {
    ice_cream: '#FF6B9D',
    salon: '#9B59B6',
    restaurant: '#E67E22',
    cafe: '#8B4513',
    pharmacy: '#27AE60',
    gym: '#E74C3C',
    spa: '#F39C12',
    retail: '#2980B9',
};
const DEFAULT_COLOUR = '#3498DB';
function borderColour(categoryType) {
    var _a;
    const slug = categoryType.toLowerCase().replace(/\s+/g, '_');
    return (_a = CATEGORY_COLOURS[slug]) !== null && _a !== void 0 ? _a : DEFAULT_COLOUR;
}
function hexToRgb(hex) {
    const h = hex.replace('#', '');
    return {
        r: parseInt(h.substring(0, 2), 16),
        g: parseInt(h.substring(2, 4), 16),
        b: parseInt(h.substring(4, 6), 16),
    };
}
function circularMask(size) {
    return Buffer.from(`<svg width="${size}" height="${size}">` +
        `<circle cx="${size / 2}" cy="${size / 2}"` +
        ` r="${size / 2}" fill="white"/>` +
        '</svg>');
}
// ─── Main ────────────────────────────────────────────────────────────────────
async function main() {
    var _a;
    console.log('\n🧪  test-doc-09 — QR Generation Smoke Test');
    console.log(`    Project : ${PROJECT_ID}`);
    console.log(`    Firestore emulator : ${(_a = process.env.FIRESTORE_EMULATOR_HOST) !== null && _a !== void 0 ? _a : '(production!)'}`);
    console.log(`    Review domain : ${REVIEW_DOMAIN}\n`);
    // ── 1. Create dummy business ────────────────────────────────────────────────
    const BIZ_ID = `test_qr_biz_${Date.now()}`;
    const BRANCH_ID = `test_qr_branch_${Date.now()}`;
    console.log('📝  Writing dummy business →', BIZ_ID);
    await db.collection('businesses').doc(BIZ_ID).set({
        brand_name: 'QR Test Parlour',
        logo_url: '', // no logo — tests the no-logo path
        category_type: 'ice_cream',
        default_category_template_id: 'ice_cream_v1',
        enrolled_by: 'test_script',
        enrolled_by_original: 'test_script',
        currently_managed_by: 'test_script',
        subscription_status: 'active',
        renewal_date: '2027-08-01',
        grace_period_ends: null,
        owner_auth_uid: null,
        created_at: firestore_1.FieldValue.serverTimestamp(),
    });
    console.log('📝  Writing dummy branch   →', `businesses/${BIZ_ID}/branches/${BRANCH_ID}`);
    await db
        .collection('businesses').doc(BIZ_ID)
        .collection('branches').doc(BRANCH_ID)
        .set({
        branch_name: 'Test Parlour — QR Branch',
        address: '1 Test Street, Mumbai, MH 400001',
        whatsapp_number: '919000000000',
        place_id: 'ChIJtest000000000000000000000000',
        google_review_link: 'https://search.google.com/local/writereview?placeid=ChIJtest000000000000000000000000',
        star_routing_config: { '1': 'whatsapp', '2': 'whatsapp', '3': 'whatsapp', '4': 'google', '5': 'google' },
        category_override_id: null,
        qr_code_id: null,
        nfc_url: null,
        stats_summary: { total_scans: 0, total_reviews_redirected: 0, last_updated: null },
        created_at: firestore_1.FieldValue.serverTimestamp(),
    });
    console.log('✓   Firestore documents written\n');
    // ── 2. Run the QR image pipeline (same logic as qrGenerator.ts) ────────────
    const categoryType = 'ice_cream';
    const reviewUrl = `https://${REVIEW_DOMAIN}/r/${BIZ_ID}/${BRANCH_ID}`;
    console.log('🔗  Review URL encoded into QR:', reviewUrl);
    const accent = borderColour(categoryType);
    const { r, g, b } = hexToRgb(accent);
    console.log('🎨  Border colour:', accent, `(${categoryType})\n`);
    // ── QR code PNG ──────────────────────────────────────────────────────────────
    const QR_SIZE = 500;
    process.stdout.write('⚙   Generating QR PNG… ');
    const qrBuffer = await QRCode.toBuffer(reviewUrl, {
        errorCorrectionLevel: 'H',
        type: 'png',
        margin: 2,
        width: QR_SIZE,
        color: { dark: '#000000', light: '#FFFFFF' },
    });
    console.log('done');
    // ── No logo in this test — skip overlay, proceed directly to border ─────────
    const logoComposites = [];
    const qrWithLogo = await (0, sharp_1.default)(qrBuffer).composite(logoComposites).png().toBuffer();
    console.log('ℹ   No logo_url set → logo overlay skipped (tests the fallback path)');
    // ── Border + resize to print dimensions ────────────────────────────────────
    const BORDER = 40;
    const PRINT_W = 1200;
    const PRINT_H = 1800;
    const TARGET_QR_SIZE = 1000;
    process.stdout.write('⚙   Applying border + resizing to 1200×1800… ');
    const qrResized = await (0, sharp_1.default)(qrWithLogo)
        .resize(TARGET_QR_SIZE - BORDER * 2, TARGET_QR_SIZE - BORDER * 2, { fit: 'inside' })
        .png()
        .toBuffer();
    const qrFinal = await (0, sharp_1.default)(qrResized)
        .extend({
        top: BORDER, bottom: BORDER, left: BORDER, right: BORDER,
        background: { r, g, b, alpha: 1 },
    })
        .png()
        .toBuffer();
    const { width: qrW, height: qrH } = await (0, sharp_1.default)(qrFinal).metadata();
    const centreLeft = Math.floor((PRINT_W - (qrW !== null && qrW !== void 0 ? qrW : 0)) / 2);
    const centreTop = Math.floor((PRINT_H - (qrH !== null && qrH !== void 0 ? qrH : 0)) / 2);
    const printReady = await (0, sharp_1.default)({
        create: { width: PRINT_W, height: PRINT_H, channels: 4, background: { r: 255, g: 255, b: 255, alpha: 1 } },
    })
        .composite([{ input: qrFinal, top: centreTop, left: centreLeft }])
        .png()
        .toBuffer();
    console.log('done');
    // ── 3. Save locally instead of uploading to Storage ─────────────────────────
    const outDir = path.resolve(process.cwd(), '.qr-test-output');
    fs.mkdirSync(outDir, { recursive: true });
    const outFile = path.join(outDir, `${BRANCH_ID}.png`);
    fs.writeFileSync(outFile, printReady);
    // ── 4. Update the branch doc with the local path (mirrors what the CF does) ─
    await db
        .collection('businesses').doc(BIZ_ID)
        .collection('branches').doc(BRANCH_ID)
        .update({
        qr_code_id: `local:${outFile}`, // "local:" prefix signals dev-only path
        nfc_url: reviewUrl,
    });
    const sizeKb = (printReady.length / 1024).toFixed(1);
    console.log('\n✅  QR generation complete!');
    console.log('─────────────────────────────────────────────────────');
    console.log('📁  Saved to      :', outFile);
    console.log('📐  Dimensions    : 1200 × 1800 px  (4×6 in @ 300 dpi, print-ready)');
    console.log('💾  File size     :', sizeKb, 'KB');
    console.log('🔗  Encoded URL   :', reviewUrl);
    console.log('🎨  Border colour :', accent);
    console.log('📄  Firestore doc :', `businesses/${BIZ_ID}/branches/${BRANCH_ID}`);
    console.log('─────────────────────────────────────────────────────');
    console.log('\nOpen the PNG to visually inspect the QR code.');
    console.log('Scan it — it should open:', reviewUrl, '\n');
    // ── Convenience: try to open the file in the default viewer on macOS ────────
    try {
        const { execSync } = await import('child_process');
        execSync(`open "${outFile}"`, { stdio: 'ignore' });
        console.log('(Auto-opened in Preview)\n');
    }
    catch (_b) {
        // Non-fatal — non-macOS or Preview not available
    }
}
main().catch((err) => {
    console.error('\n❌  Test failed:', err);
    process.exit(1);
});
//# sourceMappingURL=test-doc-09.js.map