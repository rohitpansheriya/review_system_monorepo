/**
 * scripts/test-all-statuses.js
 *
 * Seeds 7 test businesses + branches, one per subscription-lifecycle scenario:
 *
 *  tst-biz-a  active,       renewal +300 days  → normal review flow
 *  tst-biz-b  active,       renewal +30 days   → 30-day reminder window
 *  tst-biz-c  active,       renewal +15 days   → 15-day reminder window
 *  tst-biz-d  active,       renewal +7 days    → 7-day reminder window
 *  tst-biz-e  active,       renewal +1 day     → 1-day reminder window
 *  tst-biz-f  grace_period, renewal -5 days,   grace_period_ends +25 days
 *  tst-biz-g  grace_period, renewal -35 days,  grace_period_ends -2 days
 *             (tst-biz-g will be deleted when renewalLifecycle runs)
 *
 * Run against local emulator:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/test-all-statuses.js
 */

'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const PROJECT_ID   = 'review-system-prod-49b7a';
const HOSTING_PORT = 5002;
const DAY          = 86400 * 1000;

if (getApps().length === 0) {
  initializeApp({ projectId: PROJECT_ID });
}
const db = getFirestore();

function daysFromNow(n) {
  // Snap to start-of-minute to reduce clock drift in reminder Math.round()
  const d = new Date();
  d.setSeconds(0, 0);
  return new Date(d.getTime() + n * DAY);
}
function ts(date) { return Timestamp.fromDate(date); }

async function upsert(ref, data) {
  await ref.set(data, { merge: false });
  console.log('  ✓', ref.path);
}

const BUSINESSES = [
  {
    id: 'tst-biz-a', label: 'A — active +300d (baseline, no reminder)',
    status: 'active', renewalDays: 300, graceDays: null,
  },
  {
    id: 'tst-biz-b', label: 'B — active +30d (30-day reminder)',
    status: 'active', renewalDays: 30, graceDays: null,
  },
  {
    id: 'tst-biz-c', label: 'C — active +15d (15-day reminder)',
    status: 'active', renewalDays: 15, graceDays: null,
  },
  {
    id: 'tst-biz-d', label: 'D — active +7d (7-day reminder)',
    status: 'active', renewalDays: 7, graceDays: null,
  },
  {
    id: 'tst-biz-e', label: 'E — active +1d (1-day reminder)',
    status: 'active', renewalDays: 1, graceDays: null,
  },
  {
    id: 'tst-biz-f', label: 'F — grace_period, grace ends +25d (survives lifecycle)',
    status: 'grace_period', renewalDays: -5, graceDays: 25,
  },
  {
    id: 'tst-biz-g', label: 'G — grace_period, grace ended -2d (will be deleted)',
    status: 'grace_period', renewalDays: -35, graceDays: -2,
  },
];

const letterOf = id => id.replace('tst-biz-', '').toUpperCase();

async function main() {
  console.log('\n🌱 Seeding 7 lifecycle test businesses…\n');

  // Shared test employee
  await upsert(db.collection('employees').doc('tst-emp-001'), {
    name: 'Test Employee', contact: 'rohitpansheriya100@gmail.com',
    role: 'employee', active: true,
  });

  // Commission record for G (must survive deletion)
  await upsert(db.collection('commission_records').doc('tst-comm-g-001'), {
    business_id: 'tst-biz-g', employee_id: 'tst-emp-001',
    amount: 1999, payment_mode: 'cash', status: 'pending',
    date_claimed: Timestamp.now(),
  });

  console.log();

  for (const biz of BUSINESSES) {
    const branchId = biz.id.replace('biz', 'branch');
    const renewalDate = daysFromNow(biz.renewalDays);
    const bizData = {
      brand_name:           `Test Café ${letterOf(biz.id)}`,
      category_type:        'cafe',
      logo_url:             '',
      subscription_status:  biz.status,
      renewal_date:         ts(renewalDate),
      grace_period_ends:    biz.graceDays !== null ? ts(daysFromNow(biz.graceDays)) : null,
      enrolled_by:          'tst-emp-001',
      enrolled_by_original: 'tst-emp-001',
      currently_managed_by: 'tst-emp-001',
      owner_email:          'rohitpansheriya100@gmail.com',
      owner_auth_uid:       null,
    };
    const branchData = {
      branch_name:         `Test Café ${letterOf(biz.id)} — Main Branch`,
      address:             '123 Test Street, Mumbai',
      whatsapp_number:     '+919876543210',
      place_id:            `ChIJtest_${biz.id}`,
      google_review_link:  `https://g.page/r/test-${biz.id}`,
      star_routing_config: { '1':'thankyou','2':'whatsapp','3':'whatsapp','4':'google','5':'google' },
      category_override_id: null, qr_code_id: null, nfc_url: null,
      stats_summary: { total_scans: 0, total_reviews_redirected: 0, last_updated: null },
    };
    await upsert(db.collection('businesses').doc(biz.id), bizData);
    await upsert(
      db.collection('businesses').doc(biz.id).collection('branches').doc(branchId),
      branchData
    );
    console.log(`  [${letterOf(biz.id)}] ${biz.label}`);
    console.log();
  }

  console.log('✅ Seed complete.\n');
  console.log('─'.repeat(80));
  console.log('REVIEW PAGE URLs  (visit in browser BEFORE running any test scripts)');
  console.log('─'.repeat(80));

  const expected = {
    'tst-biz-a': '✅ Star rating screen  (active)',
    'tst-biz-b': '✅ Star rating screen  (active)',
    'tst-biz-c': '✅ Star rating screen  (active)',
    'tst-biz-d': '✅ Star rating screen  (active)',
    'tst-biz-e': '✅ Star rating screen  (active)',
    'tst-biz-f': '⏸️  Temporarily Paused (grace_period)',
    'tst-biz-g': '⏸️  Temporarily Paused (grace_period, not yet deleted)',
  };

  for (const biz of BUSINESSES) {
    const branchId = biz.id.replace('biz', 'branch');
    const url = `http://127.0.0.1:${HOSTING_PORT}/r/${biz.id}/${branchId}`;
    console.log(`\n  [${letterOf(biz.id)}]  ${url}`);
    console.log(`       ${expected[biz.id]}`);
  }

  console.log('\n⚠️  Timing note: run test-reminders-all.js within 1 hour of seeding.');
  console.log('   Math.round() must land on exactly 30/15/7/1 days.\n');
}

main().catch(err => { console.error('❌', err.message); process.exit(1); });
