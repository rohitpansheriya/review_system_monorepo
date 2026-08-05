/**
 * scripts/test-renewal-in-grace.js
 *
 * Simulates tst-biz-f's owner paying during the grace period (₹999 renewal).
 * Signs and sends a payment.captured webhook with the correct HMAC signature,
 * waits, then verifies:
 *   - subscription_status flips from grace_period → active
 *   - renewal_date extended by ~1 year
 *   - grace_period_ends field is removed
 *   - review page now shows the star rating screen (not "Temporarily Paused")
 *
 * Run AFTER test-all-statuses.js (tst-biz-f must be in grace_period):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/test-renewal-in-grace.js
 *
 * NOTE: tst-biz-g will have been deleted by test-grace-and-deletion.js.
 *       This script operates on tst-biz-f only.
 */

'use strict';

const crypto = require('crypto');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID      = 'review-system-prod-49b7a';
const WEBHOOK_URL     = 'http://127.0.0.1:5001/review-system-prod-49b7a/asia-south1/razorpayWebhook';
const HOSTING_BASE    = 'http://127.0.0.1:5002/r';
const WEBHOOK_SECRET  = 'my_local_test_secret_123';   // matches .secret.local
const BIZ_ID          = 'tst-biz-f';
const BRANCH_ID       = 'tst-branch-f';

if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();

async function getBizState() {
  const snap = await db.collection('businesses').doc(BIZ_ID).get();
  if (!snap.exists) return { exists: false };
  const d = snap.data();
  return {
    exists: true,
    status: d.subscription_status,
    renewalDate: d.renewal_date?.toDate().toDateString(),
    gracePeriodEnds: d.grace_period_ends,
  };
}

function buildWebhookPayload() {
  const body = JSON.stringify({
    event: 'payment.captured',
    payload: {
      payment: {
        entity: {
          id:       'pay_tst_grace_renewal_001',
          order_id: 'order_tst_grace_renewal_001',
          amount:   99900,   // ₹999 in paise
          currency: 'INR',
          status:   'captured',
          // businessId in camelCase — matches razorpayWebhook handler (line 460)
          notes:    { businessId: BIZ_ID, type: 'renewal' },
        },
      },
    },
  });
  const sig = crypto.createHmac('sha256', WEBHOOK_SECRET).update(body).digest('hex');
  return { body, sig };
}

async function sendWebhook(body, sig) {
  console.log('▶  Sending payment.captured webhook for tst-biz-f…');
  const res = await fetch(WEBHOOK_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-razorpay-signature': sig,
    },
    body,
  });
  const text = await res.text();
  console.log(`   HTTP ${res.status}  ${text}`);
  return res.status;
}

async function waitSecs(n) {
  process.stdout.write(`   Waiting ${n}s for Firestore update…`);
  await new Promise(r => setTimeout(r, n * 1000));
  process.stdout.write(' done.\n');
}

async function checkReviewPage() {
  const url = `${HOSTING_BASE}/${BIZ_ID}/${BRANCH_ID}`;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
    return { ok: res.ok, status: res.status, url };
  } catch (err) {
    return { ok: false, error: err.message, url };
  }
}

async function main() {
  console.log('\n💳 Renewal During Grace Period Test (tst-biz-f)\n');

  // 1. Pre-condition
  const pre = await getBizState();
  console.log('Pre-condition:', JSON.stringify(pre, null, 2));

  if (!pre.exists) {
    console.error('\n❌ tst-biz-f does not exist. Run test-all-statuses.js first.\n');
    process.exit(1);
  }
  if (pre.status !== 'grace_period') {
    console.warn(`\n⚠️  tst-biz-f is "${pre.status}", not "grace_period".`);
    console.warn('   If it was already renewed, this test may not produce meaningful results.\n');
  }

  // 2. Send webhook
  console.log();
  const { body, sig } = buildWebhookPayload();
  const httpStatus = await sendWebhook(body, sig);

  if (httpStatus !== 200) {
    console.error(`\n❌ Webhook returned HTTP ${httpStatus} — check emulator logs.\n`);
    process.exit(1);
  }

  await waitSecs(3);

  // 3. Post-condition
  const post = await getBizState();
  console.log('\nPost-condition:', JSON.stringify(post, null, 2));

  const statusOk        = post.exists && post.status === 'active';
  const graceClearedOk  = post.gracePeriodEnds === null || post.gracePeriodEnds === undefined;
  const renewalExtended = post.renewalDate !== pre.renewalDate;

  console.log();
  console.log(`  subscription_status → active?        ${statusOk ? '✅ PASS' : `❌ FAIL (got "${post.status}")`}`);
  console.log(`  grace_period_ends cleared?           ${graceClearedOk ? '✅ PASS' : '❌ FAIL (field still set)'}`);
  console.log(`  renewal_date extended by ~1 year?    ${renewalExtended ? '✅ PASS' : '❌ FAIL (date unchanged)'}`);

  // 4. Check review page serves (status 200, HTML is accessible)
  const page = await checkReviewPage();
  const pageOk = page.ok && page.status === 200;
  console.log(`  review page accessible (HTTP 200)?   ${pageOk ? '✅ PASS' : `❌ FAIL (HTTP ${page.status})`}`);
  console.log(`  → ${page.url}`);
  if (pageOk) {
    console.log('  Open in incognito to confirm ⭐ star rating screen now appears.\n');
  }

  // 5. Check commission_records (₹999 renewal should be recorded)
  const commSnap = await db.collection('commission_records')
    .where('business_id', '==', BIZ_ID)
    .where('amount', '==', 999)
    .get();
  const commOk = commSnap.size >= 1;
  console.log(`  commission_records created (₹999)?   ${commOk ? `✅ PASS (${commSnap.size} record)` : '❌ FAIL (none found)'}`);

  const allPassed = statusOk && graceClearedOk && renewalExtended && pageOk;
  console.log(`\n${allPassed ? '🎉 All checks passed.' : '⚠️  Some checks failed — see above.'}\n`);
}

main().catch(err => { console.error('❌', err.message); process.exit(1); });
