#!/usr/bin/env node
/**
 * fix-place-ids.js — One-time cleanup script (BUG 3)
 *
 * Scans all branches across all businesses in Firestore.
 * If any place_id contains '|' (pipe), replaces it with 'I' and
 * rebuilds the google_review_link.
 *
 * Usage:
 *   node scripts/fix-place-ids.js
 *
 * Prerequisites:
 *   - serviceAccountKey.json in project root
 *   - firebase-admin installed (npm install firebase-admin)
 */

const admin = require('firebase-admin');
const path = require('path');

const serviceAccount = require(path.resolve(__dirname, '..', 'serviceAccountKey.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function fixPlaceIds() {
  console.log('🔍 Scanning all businesses for corrupted place_ids...\\n');

  const bizSnap = await db.collection('businesses').get();
  let scanned = 0;
  let fixed = 0;

  for (const bizDoc of bizSnap.docs) {
    const branchSnap = await bizDoc.ref.collection('branches').get();

    for (const branchDoc of branchSnap.docs) {
      scanned++;
      const data = branchDoc.data();
      const placeId = data.place_id;

      if (placeId && typeof placeId === 'string' && placeId.includes('|')) {
        const corrected = placeId.replace(/\\|/g, 'I');
        const newLink = `https://search.google.com/local/writereview?placeid=${corrected}`;

        console.log(`  ❌ CORRUPTED: biz=${bizDoc.id} branch=${branchDoc.id}`);
        console.log(`     Old: ${placeId}`);
        console.log(`     New: ${corrected}`);
        console.log(`     Link: ${newLink}\\n`);

        await branchDoc.ref.update({
          place_id: corrected,
          google_review_link: newLink,
        });
        fixed++;
      }
    }
  }

  console.log(`\\n✅ Done. Scanned ${scanned} branches, fixed ${fixed} corrupted place_ids.`);
  process.exit(0);
}

fixPlaceIds().catch((err) => {
  console.error('❌ Error:', err);
  process.exit(1);
});
