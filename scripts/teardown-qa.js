/**
 * scripts/teardown-qa.js
 *
 * Deletes all QA test data (tst-qa-* businesses, their branches, and any
 * notification records they generated). Leaves lifecycle businesses (tst-biz-*)
 * and their data untouched.
 *
 * Also deletes tst-emp-002 (QA-only employee).
 *
 * Run before re-seeding for a completely clean QA slate:
 *   npm run teardown:qa
 *
 * ENVIRONMENT:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 */

'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'review-system-prod-49b7a';

if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();

// IDs of all QA businesses seeded by test-all-statuses.js
const QA_BIZ_IDS = [
  'tst-qa-bound-29',
  'tst-qa-bound-31',
  'tst-qa-bound-0',
  'tst-qa-bound-neg',
  'tst-qa-grace',
  'tst-qa-fcm-null',
  'tst-qa-fcm-bad',
  'tst-qa-emp-real',
  'tst-qa-emp-admin',
  'tst-qa-reassigned',
  'tst-qa-dig-20',
];

async function deleteCollection(collRef, batchSize = 50) {
  const snap = await collRef.limit(batchSize).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  snap.docs.forEach(d => batch.delete(d.ref));
  await batch.commit();
  // Recurse if there may be more
  if (snap.size === batchSize) {
    return snap.size + await deleteCollection(collRef, batchSize);
  }
  return snap.size;
}

async function main() {
  console.log('\n🧹 QA Teardown — removing tst-qa-* data\n');

  let totalBiz = 0;
  let totalBranches = 0;
  let totalNotifs = 0;

  for (const bizId of QA_BIZ_IDS) {
    // Delete branches sub-collection first
    const branchesRef = db.collection('businesses').doc(bizId).collection('branches');
    const branchCount = await deleteCollection(branchesRef);
    if (branchCount > 0) {
      console.log(`  🗑  businesses/${bizId}/branches  (${branchCount} doc(s))`);
      totalBranches += branchCount;
    }

    // Delete the business document itself
    const bizRef = db.collection('businesses').doc(bizId);
    const bizSnap = await bizRef.get();
    if (bizSnap.exists) {
      await bizRef.delete();
      console.log(`  🗑  businesses/${bizId}`);
      totalBiz++;
    }

    // Delete notifications written for this business
    const notifSnap = await db.collection('notifications')
      .where('business_id', '==', bizId)
      .get();
    if (!notifSnap.empty) {
      const batch = db.batch();
      notifSnap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
      console.log(`  🗑  notifications for ${bizId}  (${notifSnap.size} doc(s))`);
      totalNotifs += notifSnap.size;
    }
  }

  // Delete QA-only employee (emp-002)
  const emp2Ref = db.collection('employees').doc('tst-emp-002');
  const emp2Snap = await emp2Ref.get();
  if (emp2Snap.exists) {
    await emp2Ref.delete();
    console.log('  🗑  employees/tst-emp-002');
  }

  // Delete any stale admin_weekly_digest notifications (those have business_id=null,
  // so query them by type and recipient_role)
  const digestSnap = await db.collection('notifications')
    .where('type', '==', 'admin_weekly_digest')
    .get();
  if (!digestSnap.empty) {
    const batch = db.batch();
    digestSnap.docs.forEach(d => batch.delete(d.ref));
    await batch.commit();
    console.log(`  🗑  admin_weekly_digest notifications  (${digestSnap.size} doc(s))`);
  }

  console.log(`
✅ Teardown complete.
   Businesses deleted : ${totalBiz}
   Branches deleted   : ${totalBranches}
   Notifications del  : ${totalNotifs}

   Lifecycle businesses (tst-biz-*) and their data are UNTOUCHED.
   Run 'npm run seed && npm run test:statuses' to reseed QA businesses.
`);
}

main().catch(err => {
  console.error('❌ Teardown error:', err.message);
  process.exit(1);
});
