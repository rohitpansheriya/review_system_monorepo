/**
 * scripts/reset-firestore.js
 *
 * Safely resets Firestore transactional data for a fresh start:
 *   • Deletes all documents in `businesses` (including `branches` subcollection)
 *   • Deletes all documents in `employee_commissions` and `commission_records`
 *   • Deletes all documents in `notifications`
 *   • Deletes all documents in `scan_logs`
 *   • Deletes all documents in `subscription_override_logs`
 *   • Ensures `category_templates` are present (re-seeds if missing) so enrollment works immediately.
 *   • Leaves `employees` and Firebase Auth intact so you don't lose admin/employee login access.
 *
 * USAGE:
 *   node scripts/reset-firestore.js
 *
 * Optional flags:
 *   --include-employees   Also deletes all documents in `employees` collection
 *   --reseed-templates    Force re-seeds category templates from JSON
 */

'use strict';

const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const path = require('path');
const fs = require('fs');

const PROJECT_ID = 'review-system-prod-49b7a';
const BUCKET_NAME = 'review-system-prod-49b7a.firebasestorage.app';
const serviceKeyPath = path.resolve(__dirname, '..', 'serviceAccountKey.json');

if (getApps().length === 0) {
  if (fs.existsSync(serviceKeyPath)) {
    initializeApp({
      credential: cert(serviceKeyPath),
      projectId: PROJECT_ID,
      storageBucket: BUCKET_NAME,
    });
  } else {
    initializeApp({
      projectId: PROJECT_ID,
      storageBucket: BUCKET_NAME,
    });
  }
}

const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

async function deleteCollectionRecursively(collectionPath, batchSize = 100) {
  const collectionRef = db.collection(collectionPath);
  const snap = await collectionRef.limit(batchSize).get();
  if (snap.empty) return 0;

  let count = 0;
  for (const doc of snap.docs) {
    // Check for common subcollections
    if (collectionPath === 'businesses') {
      const branchesRef = doc.ref.collection('branches');
      const branchSnap = await branchesRef.get();
      if (!branchSnap.empty) {
        const branchBatch = db.batch();
        branchSnap.docs.forEach((b) => branchBatch.delete(b.ref));
        await branchBatch.commit();
        count += branchSnap.size;
      }
      const scansRef = doc.ref.collection('scans');
      const scansSnap = await scansRef.get();
      if (!scansSnap.empty) {
        const scanBatch = db.batch();
        scansSnap.docs.forEach((s) => scanBatch.delete(s.ref));
        await scanBatch.commit();
        count += scansSnap.size;
      }
    }
    await doc.ref.delete();
    count++;
  }

  if (snap.size >= batchSize) {
    return count + (await deleteCollectionRecursively(collectionPath, batchSize));
  }
  return count;
}

const { getStorage } = require('firebase-admin/storage');

async function deleteStorageFiles() {
  try {
    const bucket = getStorage().bucket();
    const prefixes = ['logos/', 'qr_codes/', 'plain_qr_codes/', 'standees/'];
    for (const prefix of prefixes) {
      process.stdout.write(`  Deleting Storage path: ${prefix}... `);
      await bucket.deleteFiles({ prefix, force: true });
      console.log('done');
    }
  } catch (e) {
    console.warn('  ⚠️ Could not delete storage files:', e.message);
  }
}

async function resetEmployeeCounters() {
  const empSnap = await db.collection('employees').get();
  if (empSnap.empty) return;
  const batch = db.batch();
  empSnap.docs.forEach(doc => {
    batch.update(doc.ref, {
      total_enrollments: 0,
      this_month_enrollments: 0,
      total_commissions_earned: 0,
      managed_businesses_count: 0,
    });
  });
  await batch.commit();
  console.log(`  Reset performance counters to 0 for ${empSnap.size} employee(s).`);
}

async function ensureCategoryTemplates(forceReseed = false) {
  const collectionRef = db.collection('category_templates');
  const tmplSnap = await collectionRef.get();
  
  // Check if existing docs have valid IDs (not array index "0")
  const hasValidIds = tmplSnap.docs.some(d => d.id === 'ice_cream_v1' || d.id === 'salon_v1' || d.id === 'restaurant_v1');

  if (tmplSnap.empty || !hasValidIds || forceReseed) {
    console.log('📦 Seeding category_templates with correct document IDs...');
    // Delete any old/malformed template docs first
    if (!tmplSnap.empty) {
      const delBatch = db.batch();
      tmplSnap.docs.forEach(d => delBatch.delete(d.ref));
      await delBatch.commit();
    }

    const seedPath = path.resolve(__dirname, '..', 'firestore', 'seed', 'category-templates.json');
    if (fs.existsSync(seedPath)) {
      const templates = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
      const batch = db.batch();
      for (const tpl of templates) {
        const { id, _comment, ...data } = tpl;
        batch.set(db.collection('category_templates').doc(id), data);
      }
      await batch.commit();
      console.log(`✅ Successfully seeded ${templates.length} category templates with valid IDs.`);
    } else {
      console.warn('⚠️  category-templates.json not found. Run: node scripts/generate-category-templates.js');
    }
  } else {
    console.log(`✅ category_templates collection already has ${tmplSnap.size} templates.`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const includeEmployees = args.includes('--include-employees');
  const forceReseedTemplates = args.includes('--reseed-templates');

  console.log('\n🧹 Starting Full Firestore & Storage Reset...\n');

  const collectionsToWipe = [
    'businesses',
    'employee_commissions',
    'commission_records',
    'notifications',
    'scan_logs',
    'subscription_override_logs',
    'processed_payment_events',
    'leads',
  ];

  if (includeEmployees) {
    collectionsToWipe.push('employees');
  }

  console.log('--- 1. Firestore Collections ---');
  for (const coll of collectionsToWipe) {
    process.stdout.write(`  Deleting collection: ${coll}... `);
    const deletedCount = await deleteCollectionRecursively(coll);
    console.log(`deleted ${deletedCount} doc(s)`);
  }

  console.log('\n--- 2. Employee Performance Counters ---');
  await resetEmployeeCounters();

  console.log('\n--- 3. Firebase Storage (Logos & QR Codes) ---');
  await deleteStorageFiles();

  console.log('\n--- 4. Category Templates ---');
  await ensureCategoryTemplates(forceReseedTemplates);

  console.log('\n🎉 Full reset complete! Firestore & Storage are clean and ready for your first live enrollment.\n');
}

main().catch((err) => {
  console.error('\n❌ Reset failed:', err);
  process.exit(1);
});
