/**
 * test-monthly-revenue-filter.js
 *
 * Verifies month-wise filtering for Admin Dashboard Revenue Reporting:
 * 1. All-time revenue totals.
 * 2. Filtered month (e.g., September 2026).
 * 3. Filtered month (e.g., August 2026).
 */

const assert = require('assert');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

// Point to Firestore emulator
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const app = initializeApp({ projectId: 'review-system-prod-49b7a' });
const db = getFirestore(app);

// ── Dashboard Revenue Calculation Logic with Month Filtering ──
async function computeDashboardRevenue(selectedMonth = null) {
  const snap = await db.collection('businesses').get();

  const revenueEntries = [];
  const monthSet = new Set();

  for (const doc of snap.docs) {
    const bizData = doc.data();
    const isTest = bizData['is_test_account'] === true;
    const bizStatus = bizData['subscription_status'] || 'pending_payment';
    const bizPaymentMode = bizData['payment_mode'] || 'pending';
    const isBizDraft = bizStatus === 'pending_payment';

    const branchesSnap = await doc.ref.collection('branches').get();
    const branches = branchesSnap.docs.map(bDoc => ({ id: bDoc.id, ...bDoc.data() }));

    let bActive = 0;
    for (const b of branches) {
      if (!isBizDraft && b.subscription_status === 'active') {
        bActive++;
      }
    }
    if (branches.length === 0 && !isBizDraft && bizStatus === 'active') {
      bActive = 1;
    }

    if (!isBizDraft && !isTest && (bizStatus === 'active' || bizStatus === 'grace_period')) {
      const bizSetupFeePaid = bizData['setup_fee_paid'] !== undefined ? Number(bizData['setup_fee_paid']) :
        (bizData['amount_paid'] !== undefined ? Number(bizData['amount_paid']) : null);
      const bizRenewalAmountPaid = bizData['renewal_amount_paid'] !== undefined ? Number(bizData['renewal_amount_paid']) : null;

      let setupAmount = 0.0;
      if (bizSetupFeePaid !== null && bizSetupFeePaid > 0) {
        setupAmount = bizSetupFeePaid;
      } else {
        setupAmount = (bActive > 0 ? bActive : 1) * 1999.0;
      }

      let renewalsAmount = 0.0;
      let renewalsCount = 0;
      if (bizRenewalAmountPaid !== null && bizRenewalAmountPaid > 0) {
        renewalsAmount = bizRenewalAmountPaid;
        renewalsCount = Math.round(bizRenewalAmountPaid / 999.0);
      }

      const dt = (bizData['cash_payment_confirmed_at'] && bizData['cash_payment_confirmed_at'].toDate()) ||
        (bizData['activated_at'] && bizData['activated_at'].toDate()) ||
        (bizData['created_at'] && bizData['created_at'].toDate()) ||
        new Date();

      const y = dt.getFullYear().toString().padStart(4, '0');
      const m = (dt.getMonth() + 1).toString().padStart(2, '0');
      const bizMonth = `${y}-${m}`;

      monthSet.add(bizMonth);
      revenueEntries.push({
        businessId: doc.id,
        month: bizMonth,
        paymentMode: bizPaymentMode,
        setupAmount,
        renewalsAmount,
        renewalsCount,
        activeBranches: bActive,
      });
    }
  }

  // Filter and compute
  let onlineRevenue = 0.0;
  let cashRevenue = 0.0;
  let onlineCount = 0;
  let cashCount = 0;
  let renewalsRevenue = 0.0;
  let renewalsCount = 0;

  for (const entry of revenueEntries) {
    if (selectedMonth !== null && entry.month !== selectedMonth) {
      continue;
    }
    if (entry.paymentMode === 'cash') {
      cashRevenue += entry.setupAmount;
      cashCount += 1;
    } else {
      onlineRevenue += entry.setupAmount;
      onlineCount += 1;
    }
    renewalsRevenue += entry.renewalsAmount;
    renewalsCount += entry.renewalsCount;
  }

  const newEnrollmentsRevenue = onlineRevenue + cashRevenue;
  const totalRevenueSnapshot = newEnrollmentsRevenue + renewalsRevenue;

  return {
    availableMonths: Array.from(monthSet).sort().reverse(),
    onlineRevenue,
    cashRevenue,
    onlineCount,
    cashCount,
    newEnrollmentsRevenue,
    renewalsRevenue,
    renewalsCount,
    totalRevenueSnapshot,
  };
}

async function runTest() {
  console.log('🧪 Starting Month-Wise Revenue Filter Test Suite...\n');

  // Clear previous businesses
  const existing = await db.collection('businesses').get();
  for (const doc of existing.docs) {
    const branches = await doc.ref.collection('branches').get();
    for (const b of branches.docs) await b.ref.delete();
    await doc.ref.delete();
  }

  const dateSept2026 = Timestamp.fromDate(new Date('2026-09-02T10:00:00Z'));
  const dateAug2026 = Timestamp.fromDate(new Date('2026-08-15T10:00:00Z'));

  // 1. Business A: Enrolled in Sept 2026 (₹1,999 Online Setup + ₹999 Renewal)
  console.log('1️⃣ Seeding Sept 2026 Business (₹1,999 Online Setup + ₹999 Renewal)...');
  const bizA = db.collection('businesses').doc('month_test_sept_a');
  await bizA.set({
    brand_name: 'Sept Boutique',
    subscription_status: 'active',
    payment_mode: 'online',
    setup_fee_paid: 1999,
    renewal_amount_paid: 999,
    amount_paid: 2998,
    created_at: dateSept2026,
    activated_at: dateSept2026,
    is_test_account: false,
  });

  // 2. Business B: Enrolled in Aug 2026 (5 branches paid ₹4,999 Cash)
  console.log('2️⃣ Seeding Aug 2026 Multi-Branch Business (₹4,999 Cash Setup)...');
  const bizB = db.collection('businesses').doc('month_test_aug_b');
  await bizB.set({
    brand_name: 'Aug Mega Store',
    subscription_status: 'active',
    payment_mode: 'cash',
    setup_fee_paid: 4999,
    amount_paid: 4999,
    created_at: dateAug2026,
    activated_at: dateAug2026,
    is_test_account: false,
  });

  // Test 1: All Time
  console.log('\n--- TEST 1: All-Time Revenue Total ---');
  const allTime = await computeDashboardRevenue(null);
  console.log(`Available Months: ${allTime.availableMonths.join(', ')}`);
  console.log(`All-Time Total Revenue: ₹${allTime.totalRevenueSnapshot}`);
  assert.strictEqual(allTime.totalRevenueSnapshot, 1999 + 999 + 4999); // 7997
  assert.strictEqual(allTime.onlineRevenue, 1999);
  assert.strictEqual(allTime.cashRevenue, 4999);
  assert.strictEqual(allTime.renewalsRevenue, 999);
  console.log('✅ PASS: All-time matches ₹7,997 (₹1,999 online + ₹4,999 cash + ₹999 renewal).');

  // Test 2: Filter by '2026-09'
  console.log('\n--- TEST 2: Filter by September 2026 (2026-09) ---');
  const septStats = await computeDashboardRevenue('2026-09');
  console.log(`Sept Total Revenue: ₹${septStats.totalRevenueSnapshot}`);
  console.log(`Sept Online Revenue: ₹${septStats.onlineRevenue}`);
  console.log(`Sept Cash Revenue: ₹${septStats.cashRevenue}`);
  console.log(`Sept Renewals: ₹${septStats.renewalsRevenue}`);
  assert.strictEqual(septStats.totalRevenueSnapshot, 1999 + 999); // 2998
  assert.strictEqual(septStats.onlineRevenue, 1999);
  assert.strictEqual(septStats.cashRevenue, 0); // No cash in Sept
  assert.strictEqual(septStats.renewalsRevenue, 999);
  console.log('✅ PASS: September 2026 correctly isolates ₹2,998 (₹1,999 setup + ₹999 renewal).');

  // Test 3: Filter by '2026-08'
  console.log('\n--- TEST 3: Filter by August 2026 (2026-08) ---');
  const augStats = await computeDashboardRevenue('2026-08');
  console.log(`Aug Total Revenue: ₹${augStats.totalRevenueSnapshot}`);
  console.log(`Aug Online Revenue: ₹${augStats.onlineRevenue}`);
  console.log(`Aug Cash Revenue: ₹${augStats.cashRevenue}`);
  assert.strictEqual(augStats.totalRevenueSnapshot, 4999);
  assert.strictEqual(augStats.onlineRevenue, 0);
  assert.strictEqual(augStats.cashRevenue, 4999);
  assert.strictEqual(augStats.renewalsRevenue, 0);
  console.log('✅ PASS: August 2026 correctly isolates ₹4,999 cash setup revenue.');

  console.log('\n🎉 ALL MONTH-WISE REVENUE FILTER TESTS PASSED SUCCESSFULLY!');
}

runTest().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
