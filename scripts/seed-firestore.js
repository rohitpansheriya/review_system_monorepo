/**
 * scripts/seed-firestore.js
 *
 * Seeds Firestore with:
 *   • category_templates   (from firestore/seed/category-templates.json)
 *   • businesses           (from firestore/seed/test-data.json)
 *   • branches             (sub-collection of businesses)
 *
 * ─── LOCAL EMULATOR (no credentials needed) ────────────────────────────────
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/seed-firestore.js
 *
 * ─── PRODUCTION (requires a service account key) ───────────────────────────
 *
 *   1. Download a service account key from Firebase console:
 *      Project Settings → Service Accounts → Generate new private key
 *      Save the JSON file to the repo root (it is gitignored via
 *      *firebase-adminsdk*.json in .gitignore — NEVER commit it).
 *
 *   2. Run with GOOGLE_APPLICATION_CREDENTIALS pointing at that key:
 *
 *      GOOGLE_APPLICATION_CREDENTIALS="./review-system-prod-49b7a-firebase-adminsdk-fbsvc-XXXXX.json" \
 *        node scripts/seed-firestore.js
 *
 *   Without GOOGLE_APPLICATION_CREDENTIALS the Admin SDK falls back to
 *   Application Default Credentials (ADC), which works inside Cloud Shell
 *   or on a GCE instance but NOT from a local Mac terminal.
 *
 * ─── Prerequisites ──────────────────────────────────────────────────────────
 *
 *   npm install   (run once in the repo root to install firebase-admin)
 */

'use strict';

// firebase-admin v10+ uses subpath exports — import app and firestore separately.
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore }           = require('firebase-admin/firestore');
const path = require('path');
const fs   = require('fs');

// ---------------------------------------------------------------------------
// Initialise Admin SDK (idempotent — safe to require from multiple scripts)
// ---------------------------------------------------------------------------
const projectId = process.env.GCLOUD_PROJECT
               || process.env.FIREBASE_PROJECT_ID
               || 'review-system-prod-49b7a';   // fallback — update if project ID changes

if (getApps().length === 0) {
  initializeApp({
    // When GOOGLE_APPLICATION_CREDENTIALS is set the SDK picks it up automatically.
    // When running inside GCP (Cloud Run, Cloud Functions) ADC is used — no extra setup.
    // When FIRESTORE_EMULATOR_HOST is set the SDK routes all traffic to the emulator.
    projectId,
  });
}

const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

// ---------------------------------------------------------------------------
// Load seed files
// ---------------------------------------------------------------------------
const SEED_DIR      = path.join(__dirname, '../firestore/seed');
const templates     = JSON.parse(fs.readFileSync(path.join(SEED_DIR, 'category-templates.json'), 'utf8'));
const testData      = JSON.parse(fs.readFileSync(path.join(SEED_DIR, 'test-data.json'),         'utf8'));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
async function upsert(ref, data) {
  await ref.set(data, { merge: true });
  console.log('  ✓', ref.path);
}

// ---------------------------------------------------------------------------
// Main seed function
// ---------------------------------------------------------------------------
async function seed() {
  console.log(`\n🌱 Seeding Firestore project: ${projectId}\n`);

  // ---- 1. category_templates -----------------------------------------------
  console.log('📂 category_templates');
  for (const tpl of templates) {
    const { id, _comment, ...rest } = tpl;   // strip _comment
    await upsert(db.collection('category_templates').doc(id), rest);
  }

  // ---- 2. businesses -------------------------------------------------------
  console.log('\n📂 businesses');
  for (const biz of testData.businesses) {
    await upsert(db.collection('businesses').doc(biz.id), biz.data);
  }

  // ---- 3. branches (sub-collection) ----------------------------------------
  console.log('\n📂 branches');
  for (const branch of testData.branches) {
    const ref = db
      .collection('businesses').doc(branch.business_id)
      .collection('branches').doc(branch.id);
    await upsert(ref, branch.data);
  }

  console.log('\n✅ Seed complete.\n');
  console.log('Test URLs (Firestore emulator or production):');
  for (const branch of testData.branches) {
    console.log(`  /r/${branch.id}  →  businesses/${branch.business_id}/branches/${branch.id}`);
  }
}

seed().catch(err => {
  console.error('❌ Seed failed:', err);
  process.exit(1);
});
