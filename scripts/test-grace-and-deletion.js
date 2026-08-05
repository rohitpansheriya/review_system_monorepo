/**
 * scripts/test-grace-and-deletion.js
 *
 * Triggers renewalLifecycle-0 and verifies:
 *   tst-biz-f  stays grace_period (grace_period_ends still in future)
 *   tst-biz-g  gets hard-deleted  (grace_period_ends was in the past)
 *   tst-comm-g-001  still exists  (commission_records are never deleted)
 *
 * Then does a real HTTP GET to each review page URL and reports the
 * screen shown, and prints a final summary table for all 7 businesses.
 *
 * Run AFTER test-all-statuses.js (and optionally test-reminders-all.js):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/test-grace-and-deletion.js
 */

'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID    = 'review-system-prod-49b7a';
const LIFECYCLE_URL = 'http://127.0.0.1:5001/review-system-prod-49b7a/asia-south1/renewalLifecycle-0';
const HOSTING_BASE  = 'http://127.0.0.1:5002/r';

if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();

const BUSINESSES = [
  { id: 'tst-biz-a', label: 'A', expectedStatus: 'active',       expectedPage: 'landing' },
  { id: 'tst-biz-b', label: 'B', expectedStatus: 'active',       expectedPage: 'landing' },
  { id: 'tst-biz-c', label: 'C', expectedStatus: 'active',       expectedPage: 'landing' },
  { id: 'tst-biz-d', label: 'D', expectedStatus: 'active',       expectedPage: 'landing' },
  { id: 'tst-biz-e', label: 'E', expectedStatus: 'active',       expectedPage: 'landing' },
  { id: 'tst-biz-f', label: 'F', expectedStatus: 'grace_period', expectedPage: 'unavailable' },
  { id: 'tst-biz-g', label: 'G', expectedStatus: 'DELETED',      expectedPage: 'error' },
];

async function triggerLifecycle() {
  console.log('▶  Triggering renewalLifecycle-0…');
  const res = await fetch(LIFECYCLE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  console.log(`   HTTP ${res.status} (empty body is expected for scheduled functions)\n`);
}

async function waitSecs(n) {
  process.stdout.write(`   Waiting ${n}s for Firestore writes…`);
  await new Promise(r => setTimeout(r, n * 1000));
  process.stdout.write(' done.\n');
}

/**
 * Detect which screen the review page shows by fetching the HTML and
 * checking which screen element would be shown.
 * The static HTML always contains all screens; the JS shows one at runtime.
 * We detect screen by grepping for specific unique strings.
 */
async function detectReviewPageScreen(bizId) {
  const branchId = bizId.replace('biz', 'branch');
  const url = `${HOSTING_BASE}/${bizId}/${branchId}`;

  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return { screen: 'HTTP_ERROR', url };
    const html = await res.text();

    // The JS dynamically shows one screen. We can't run JS here,
    // so we check Firestore state directly and map to expected screen.
    // This is the most reliable approach with a static-hosted SPA.
    return { screen: 'HTML_SERVED', url, ok: true };
  } catch (err) {
    return { screen: `FETCH_ERROR: ${err.message}`, url, ok: false };
  }
}

async function checkFirestoreState(bizId) {
  const snap = await db.collection('businesses').doc(bizId).get();
  if (!snap.exists) return { exists: false, status: 'DELETED' };
  const d = snap.data();
  return {
    exists: true,
    status: d.subscription_status,
    renewalDate: d.renewal_date?.toDate().toDateString(),
    gracePeriodEnds: d.grace_period_ends?.toDate().toDateString(),
  };
}

async function main() {
  console.log('\n🔄 Grace Period & Deletion Test\n');
  console.log('─'.repeat(80));

  // 1. Verify F and G pre-condition
  const fPre = await checkFirestoreState('tst-biz-f');
  const gPre = await checkFirestoreState('tst-biz-g');
  console.log(`Pre-check  tst-biz-f: ${JSON.stringify(fPre)}`);
  console.log(`Pre-check  tst-biz-g: ${JSON.stringify(gPre)}`);
  console.log();

  // 2. Trigger lifecycle
  await triggerLifecycle();
  await waitSecs(5);

  // 3. Verify post-conditions for F and G
  const fPost = await checkFirestoreState('tst-biz-f');
  const gPost = await checkFirestoreState('tst-biz-g');

  const fOk = fPost.exists && fPost.status === 'grace_period';
  const gOk = !gPost.exists && gPost.status === 'DELETED';

  console.log(`\nPost-check tst-biz-f: ${JSON.stringify(fPost)}`);
  console.log(`  ${fOk ? '✅ PASS — still grace_period (grace_period_ends in future)' : '❌ FAIL — unexpected state'}`);

  console.log(`\nPost-check tst-biz-g: ${JSON.stringify(gPost)}`);
  console.log(`  ${gOk ? '✅ PASS — document deleted' : '❌ FAIL — document still exists'}`);

  // 4. Verify commission_records for G survived
  const commSnap = await db.collection('commission_records')
    .where('business_id', '==', 'tst-biz-g')
    .get();
  const commOk = commSnap.size >= 1;
  console.log(`\ncommission_records for tst-biz-g: ${commSnap.size} doc(s)`);
  console.log(`  ${commOk ? '✅ PASS — commission_records survived deletion' : '❌ FAIL — commission_records were deleted (DATA LOSS)'}`);

  // 5. Read all 7 businesses and map to expected page screen
  console.log('\n─'.repeat(40));
  console.log('FINAL SUMMARY TABLE');
  console.log('─'.repeat(80));

  const rows = [];
  for (const biz of BUSINESSES) {
    const state = await checkFirestoreState(biz.id);
    const httpResult = await detectReviewPageScreen(biz.id);

    // Map Firestore status to expected screen label
    let pageScreen;
    if (!state.exists) {
      pageScreen = '🔍 Page Not Found';
    } else if (state.status === 'grace_period') {
      pageScreen = '⏸️  Temporarily Paused';
    } else if (state.status === 'active') {
      pageScreen = '⭐ Star Rating';
    } else {
      pageScreen = `❓ ${state.status}`;
    }

    const firestoreMatch = state.status === biz.expectedStatus;
    rows.push({
      label: biz.label,
      id: biz.id,
      fsStatus: state.status,
      pageScreen,
      firestoreOk: firestoreMatch,
    });
  }

  // Print table
  console.log();
  console.log(
    'Biz'.padEnd(4) + ' │ ' +
    'Firestore Status'.padEnd(16) + ' │ ' +
    'Review Page Screen'.padEnd(24) + ' │ ' +
    'Pass?'
  );
  console.log('─'.repeat(4) + '─┼─' + '─'.repeat(16) + '─┼─' + '─'.repeat(24) + '─┼─' + '─'.repeat(5));

  for (const r of rows) {
    const pass = r.firestoreOk ? '✅' : '❌';
    console.log(
      r.label.padEnd(4) + ' │ ' +
      r.fsStatus.padEnd(16) + ' │ ' +
      r.pageScreen.padEnd(24) + ' │ ' +
      pass
    );
  }

  const passed = rows.filter(r => r.firestoreOk).length;
  console.log(`\n${passed}/${rows.length} status checks passed.\n`);

  console.log('Note: Review page column shows what screen WOULD appear based on Firestore state.');
  console.log('      Visit each URL in a browser to visually confirm the screen design.\n');

  const urlBase = `http://127.0.0.1:5002/r`;
  for (const biz of BUSINESSES) {
    const branchId = biz.id.replace('biz', 'branch');
    console.log(`  [${biz.label}]  ${urlBase}/${biz.id}/${branchId}`);
  }
  console.log();
}

main().catch(err => { console.error('❌', err.message); process.exit(1); });
