/**
 * scripts/test-all-statuses.js
 *
 * Seeds 8 lifecycle test businesses (A–H) + 11 QA-specific businesses
 * for the notifications system QA test plan (T1–T14).
 *
 * Lifecycle businesses:
 *  tst-biz-a  active,       renewal +300 days  → normal review flow
 *  tst-biz-b  active,       renewal +30 days   → 30-day reminder window
 *  tst-biz-c  active,       renewal +15 days   → 15-day reminder window
 *  tst-biz-d  active,       renewal +7 days    → 7-day reminder window
 *  tst-biz-e  active,       renewal +1 day     → 1-day reminder window
 *  tst-biz-f  grace_period, renewal -5 days,   grace_period_ends +25 days
 *  tst-biz-g  grace_period, renewal -35 days,  grace_period_ends -2 days
 *  tst-biz-h  active,       renewal +7 days,   enrolled_by=admin
 *
 * QA businesses (tst-qa-*):
 *  tst-qa-bound-29   T1 — +29d boundary (should NOT fire)
 *  tst-qa-bound-31   T2 — +31d boundary (should NOT fire)
 *  tst-qa-bound-0    T3 — day 0 (should NOT fire)
 *  tst-qa-bound-neg  T4 — -1d past renewal (should NOT fire)
 *  tst-qa-grace      T6 — grace_period status gate (should NOT fire)
 *  tst-qa-fcm-null   T8 — FCM null → push skipped, email+Firestore ok
 *  tst-qa-fcm-bad    T9 — FCM garbage token → FCM fails isolated
 *  tst-qa-emp-real   T11 — real employee → owner + employee notified
 *  tst-qa-emp-admin  T12 — enrolled_by=admin → owner only
 *  tst-qa-reassigned T13 — reassigned to emp-002 → emp-002 notified
 *  tst-qa-dig-20     T14 — +20d, contributes to admin digest pool
 *
 * Run against local emulator:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/test-all-statuses.js
 */

'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const PROJECT_ID = 'review-system-prod-49b7a';
const HOSTING_PORT = 5002;
const DAY = 86400 * 1000;

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
  {
    id: 'tst-biz-h', label: 'H — active +7d, enrolled_by=admin (employee skip test)',
    status: 'active', renewalDays: 7, graceDays: null, enrolledByAdmin: true,
  },
];

// ─── QA test businesses (T1–T14) ────────────────────────────────────────────
const QA_BUSINESSES = [
  // T1 — boundary: +29d (Math.round(29)=29, NOT in WINDOWS [30,15,7,1])
  { id: 'tst-qa-bound-29',  label: 'QA/T1 — active +29d (should NOT fire)',       status: 'active',       renewalDays: 29,  graceDays: null },
  // T2 — boundary: +31d (Math.round(31)=31, NOT in WINDOWS)
  { id: 'tst-qa-bound-31',  label: 'QA/T2 — active +31d (should NOT fire)',       status: 'active',       renewalDays: 31,  graceDays: null },
  // T3 — boundary: day 0 (Math.round(0)=0, NOT in WINDOWS)
  { id: 'tst-qa-bound-0',   label: 'QA/T3 — active +0d renewal today (no fire)',  status: 'active',       renewalDays: 0,   graceDays: null },
  // T4 — boundary: -1d past renewal, still active in Firestore (lifecycle not yet run)
  { id: 'tst-qa-bound-neg', label: 'QA/T4 — active -1d past renewal (no fire)',   status: 'active',       renewalDays: -1,  graceDays: null },
  // T6 — grace_period: daysDiff < 0, NOT in WINDOWS → no reminder
  { id: 'tst-qa-grace',     label: 'QA/T6 — grace_period -10d (no reminder)',     status: 'grace_period', renewalDays: -10, graceDays: 20 },
  // T8 — FCM null token → push skipped, email+Firestore succeed
  { id: 'tst-qa-fcm-null',  label: 'QA/T8 — active +7d, fcm_token=null',          status: 'active',       renewalDays: 7,   graceDays: null },
  // T9 — FCM garbage token → FCM throws, but email+Firestore already done
  { id: 'tst-qa-fcm-bad',   label: 'QA/T9 — active +7d, fcm_token=garbage',       status: 'active',       renewalDays: 7,   graceDays: null, fcmToken: 'garbage_invalid_fcm_token_qa_xyz' },
  // T11 — real employee → both notified
  { id: 'tst-qa-emp-real',   label: 'QA/T11 — active +7d, enrolled_by=real emp',  status: 'active',       renewalDays: 7,   graceDays: null },
  // T12 — enrolled_by=admin → owner only
  { id: 'tst-qa-emp-admin',  label: 'QA/T12 — active +7d, enrolled_by=admin',     status: 'active',       renewalDays: 7,   graceDays: null, enrolledByAdmin: true },
  // T13 — reassigned to emp-002 → emp-002 notified, not emp-001
  { id: 'tst-qa-reassigned', label: 'QA/T13 — active +7d, managed_by=emp-002',    status: 'active',       renewalDays: 7,   graceDays: null, reassignedToEmp2: true },
  // T14 — +20d contributes to admin digest pool
  { id: 'tst-qa-dig-20',    label: 'QA/T14 — active +20d (admin digest pool)',    status: 'active',       renewalDays: 20,  graceDays: null },
];

const letterOf = id => id.replace('tst-biz-', '').toUpperCase();

async function main() {
  console.log('\n🌱 Seeding lifecycle businesses + QA businesses…\n');

  // ── Shared test employee (Employee 1) ─────────────────────────────
  await upsert(db.collection('employees').doc('tst-emp-001'), {
    name: 'Test Employee 1', contact: 'rohitpansheriya100@gmail.com',
    role: 'employee', active: true,
  });

  // ── Employee 2 — for T13 (reassignment) ───────────────────────────
  await upsert(db.collection('employees').doc('tst-emp-002'), {
    name: 'Test Employee 2', contact: 'rohitpansheriya100@gmail.com',
    role: 'employee', active: true,
  });

  // Commission record for G (must survive deletion)
  await upsert(db.collection('commission_records').doc('tst-comm-g-001'), {
    business_id: 'tst-biz-g', employee_id: 'tst-emp-001',
    amount: 1999, payment_mode: 'cash', status: 'pending',
    date_claimed: Timestamp.now(),
  });

  console.log();

  // ── Build function for a single business document ─────────────────
  function buildBizData(biz, renewalDate) {
    let enrolledBy = 'tst-emp-001';
    let currentlyManagedBy = 'tst-emp-001';
    if (biz.enrolledByAdmin) {
      enrolledBy = 'admin';
      currentlyManagedBy = 'admin';
    } else if (biz.reassignedToEmp2) {
      // Originally enrolled by emp-001, now managed by emp-002
      currentlyManagedBy = 'tst-emp-002';
    }
    return {
      brand_name:           `Test Café ${biz.id.replace('tst-', '').toUpperCase()}`,
      category_type:        'cafe',
      logo_url:             '',
      subscription_status:  biz.status,
      renewal_date:         ts(renewalDate),
      grace_period_ends:    biz.graceDays !== null ? ts(daysFromNow(biz.graceDays)) : null,
      enrolled_by:          enrolledBy,
      enrolled_by_original: 'tst-emp-001',
      currently_managed_by: currentlyManagedBy,
      owner_email:          'rohitpansheriya100@gmail.com',
      owner_auth_uid:       null,
      // FCM token: null for most; garbage string for T9 channel-isolation test.
      // Real tokens populated by Flutter panel at login (doc 02/03).
      owner_fcm_token:      biz.fcmToken ?? null,
    };
  }

  // ── Seed lifecycle businesses (A–H) ────────────────────────────────
  console.log('  [Lifecycle businesses A–H]');
  for (const biz of BUSINESSES) {
    const branchId = biz.id.replace('biz', 'branch');
    const renewalDate = daysFromNow(biz.renewalDays);
    const bizData = buildBizData(biz, renewalDate);
    const branchData = {
      branch_name: `Test Café ${biz.id.replace('tst-biz-', '').toUpperCase()} — Main Branch`,
      address: '123 Test Street, Mumbai',
      whatsapp_number: '+919876543210',
      place_id: `ChIJtest_${biz.id}`,
      google_review_link: `https://g.page/r/test-${biz.id}`,
      star_routing_config: { '1': 'thankyou', '2': 'whatsapp', '3': 'whatsapp', '4': 'google', '5': 'google' },
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

  // ── Seed QA businesses (tst-qa-*) ──────────────────────────────────
  console.log('\n  [QA businesses — T1-T14]');
  for (const biz of QA_BUSINESSES) {
    const branchId = biz.id.replace('tst-qa-', 'tst-qa-branch-').replace('-bound-', '-br-').replace('-fcm-', '-br-').replace('-emp-', '-br-').replace('-dig-', '-br-');
    const renewalDate = daysFromNow(biz.renewalDays);
    const bizData = buildBizData(biz, renewalDate);
    // Override brand_name to be human-readable for QA
    bizData.brand_name = biz.label.split(' — ')[0].replace('QA/', '[QA] ');
    const branchData = {
      branch_name: `${biz.id} branch`,
      address: '123 QA Street, Mumbai',
      whatsapp_number: '+919876543210',
      place_id: `ChIJqa_${biz.id}`,
      google_review_link: `https://g.page/r/qa-${biz.id}`,
      star_routing_config: { '1': 'thankyou', '2': 'whatsapp', '3': 'whatsapp', '4': 'google', '5': 'google' },
      category_override_id: null, qr_code_id: null, nfc_url: null,
      stats_summary: { total_scans: 0, total_reviews_redirected: 0, last_updated: null },
    };
    await upsert(db.collection('businesses').doc(biz.id), bizData);
    await upsert(
      db.collection('businesses').doc(biz.id).collection('branches').doc(branchId),
      branchData
    );
    console.log(`  [QA] ${biz.label}`);
  }

  console.log('\n✅ Seed complete.');
  console.log('─'.repeat(80));
  console.log('REVIEW PAGE URLs  (lifecycle businesses — visit in browser)');
  console.log('─'.repeat(80));

  const expected = {
    'tst-biz-a': '✅ Star rating screen  (active)',
    'tst-biz-b': '✅ Star rating screen  (active)',
    'tst-biz-c': '✅ Star rating screen  (active)',
    'tst-biz-d': '✅ Star rating screen  (active)',
    'tst-biz-e': '✅ Star rating screen  (active)',
    'tst-biz-f': '⏸️  Temporarily Paused (grace_period)',
    'tst-biz-g': '⏸️  Temporarily Paused (grace_period, not yet deleted)',
    'tst-biz-h': '✅ Star rating screen  (active, enrolled_by=admin)',
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
