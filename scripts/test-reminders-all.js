/**
 * scripts/test-reminders-all.js
 *
 * Triggers sendRenewalReminders-0, then reads Firestore to confirm
 * Businesses B/C/D/E each got 2 notifications (owner + employee)
 * and Business A got none (too far out).
 *
 * Run AFTER test-all-statuses.js, within the same hour:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/test-reminders-all.js
 */

'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'review-system-prod-49b7a';
const FUNCTIONS_URL = 'http://127.0.0.1:5001/review-system-prod-49b7a/asia-south1/sendRenewalReminders-0';

if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();

const BUSINESSES = ['tst-biz-a', 'tst-biz-b', 'tst-biz-c', 'tst-biz-d', 'tst-biz-e'];
const EXPECTED_TYPE = {
  'tst-biz-a': null,
  'tst-biz-b': 'renewal_reminder_30',
  'tst-biz-c': 'renewal_reminder_15',
  'tst-biz-d': 'renewal_reminder_7',
  'tst-biz-e': 'renewal_reminder_1',
};

async function triggerFunction() {
  console.log('▶  Triggering sendRenewalReminders-0…');
  const res = await fetch(FUNCTIONS_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  console.log(`   HTTP ${res.status}`);
}

async function waitSecs(n) {
  console.log(`   Waiting ${n}s for async processing…`);
  await new Promise(r => setTimeout(r, n * 1000));
}

async function checkNotifications() {
  const results = [];

  for (const bizId of BUSINESSES) {
    const snap = await db.collection('notifications')
      .where('business_id', '==', bizId)
      .get();

    const notifs = snap.docs.map(d => d.data());
    const types = [...new Set(notifs.map(n => n.type))];
    const roles = notifs.map(n => n.recipient_role).sort();
    const expected = EXPECTED_TYPE[bizId];

    let status;
    if (expected === null) {
      status = snap.size === 0 ? '✅ PASS — no notification (correct)' : `❌ FAIL — got ${snap.size} unexpected notifications`;
    } else {
      const hasCorrectType = types.includes(expected);
      const hasOwner = roles.includes('owner');
      const hasEmp = roles.includes('employee');
      if (hasCorrectType && hasOwner && hasEmp && snap.size === 2) {
        status = `✅ PASS — ${expected} × 2 (owner + employee)`;
      } else {
        status = `❌ FAIL — expected ${expected} × 2, got [${types.join(',')}] × ${snap.size} [${roles.join(',')}]`;
      }
    }

    // Read business to show actual renewal_date
    const bizSnap = await db.collection('businesses').doc(bizId).get();
    const renewal = bizSnap.data()?.renewal_date?.toDate();
    const daysLeft = renewal
      ? Math.round((renewal - new Date()) / 86400000)
      : '?';

    results.push({
      bizId,
      daysLeft,
      expected: expected ?? '(none)',
      count: snap.size,
      status,
    });
  }
  return results;
}

async function main() {
  console.log('\n📬 Reminder Test\n');

  await triggerFunction();
  await waitSecs(4);

  console.log('\nChecking notifications collection…\n');
  const results = await checkNotifications();

  // Print table
  const COL = [14, 10, 24, 7];
  const header = ['Business', 'Days Left', 'Expected Type', 'Count'];
  const divider = COL.map(w => '─'.repeat(w)).join('─┼─');
  const row = (cells) => cells.map((c, i) => String(c).padEnd(COL[i])).join(' │ ');

  console.log(row(header));
  console.log(divider);
  results.forEach(r => {
    console.log(row([r.bizId, r.daysLeft, r.expected, r.count]));
    console.log('  ' + r.status);
  });

  const passed = results.filter(r => r.status.startsWith('✅')).length;
  console.log(`\n${passed}/${results.length} checks passed.\n`);

  if (passed < results.length) {
    console.log('⚠️  Failures may indicate:');
    console.log('   - More than 1 hour since seeding (Math.round drifted to wrong day)');
    console.log('   - Idempotency guard fired (reminders already sent to this business_id+type)');
    console.log('   - Brevo API key invalid (but Firestore write still happens)');
    console.log('   Re-run test-all-statuses.js to reseed with fresh timestamps, then retry.\n');
  }
}

main().catch(err => { console.error('❌', err.message); process.exit(1); });
