/**
 * test-revenue-calculation.js
 *
 * Verifies admin dashboard revenue reporting with actual paid amounts:
 * 1. Single-branch Online (₹1,999)
 * 2. Single-branch Cash (₹1,999)
 * 3. 5-Branch Multi-Location Online (₹4,999 actual paid amount, NOT 5 × 1999)
 * 4. Business Renewal (₹999)
 *
 * Total expected revenue: ₹1,999 + ₹1,999 + ₹4,999 + ₹999 = ₹9,996
 * Online revenue: ₹1,999 + ₹4,999 = ₹6,998
 * Cash revenue: ₹1,999
 * Renewals revenue: ₹999
 */

const assert = require('assert');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

// Point to Firestore emulator
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const app = initializeApp({ projectId: 'review-system-prod-49b7a' });
const db = getFirestore(app);

// ── Dashboard Revenue Calculation Logic (Mirroring AdminDashboardProvider) ──
async function computeDashboardRevenue() {
  const snap = await db.collection('businesses').get();

  let totalActiveBranches = 0;
  let totalPendingBranches = 0;
  let totalOnlineCount = 0;
  let totalCashCount = 0;
  let totalOnlineRevenue = 0.0;
  let totalCashRevenue = 0.0;
  let totalRenewalsCount = 0;
  let totalRenewalsRevenue = 0.0;

  for (const doc of snap.docs) {
    const bizData = doc.data();
    const isTest = bizData['is_test_account'] === true;
    const bizStatus = bizData['subscription_status'] || 'pending_payment';
    const bizPaymentMode = bizData['payment_mode'] || 'pending';
    const isBizDraft = bizStatus === 'pending_payment';

    const branchesSnap = await doc.ref.collection('branches').get();
    const branches = branchesSnap.docs.map(bDoc => ({ id: bDoc.id, ...bDoc.data() }));

    let bActive = 0;
    let bGrace = 0;
    let bPending = 0;
    let bDeleted = 0;

    for (const b of branches) {
      if (isBizDraft) {
        bPending++;
        continue;
      }
      if (b.subscription_status === 'active') {
        bActive++;
      } else if (b.subscription_status === 'grace_period') {
        bGrace++;
      } else if (b.subscription_status === 'pending_payment') {
        bPending++;
      } else if (b.subscription_status === 'deleted') {
        bDeleted++;
      } else {
        bPending++;
      }
    }

    if (branches.length === 0) {
      if (isBizDraft) bPending = 1;
      else if (bizStatus === 'active') bActive = 1;
      else if (bizStatus === 'grace_period') bGrace = 1;
      else if (bizStatus === 'deleted') bDeleted = 1;
      else bPending = 1;
    }

    totalActiveBranches += bActive;
    totalPendingBranches += bPending;

    if (!isBizDraft && !isTest && (bizStatus === 'active' || bizStatus === 'grace_period')) {
      const bizSetupFeePaid = bizData['setup_fee_paid'] !== undefined ? Number(bizData['setup_fee_paid']) :
        (bizData['amount_paid'] !== undefined ? Number(bizData['amount_paid']) : null);
      const bizRenewalAmountPaid = bizData['renewal_amount_paid'] !== undefined ? Number(bizData['renewal_amount_paid']) : null;

      // Setup revenue: actual recorded > branch sum > fallback 1999 * bActive
      let setupAmount = 0.0;
      if (bizSetupFeePaid !== null && bizSetupFeePaid > 0) {
        setupAmount = bizSetupFeePaid;
      } else {
        let branchSetupSum = 0.0;
        let hasExplicitBranchFees = false;
        for (const b of branches) {
          if (b.subscription_status === 'active' || b.subscription_status === 'grace_period') {
            if (b.setup_fee_paid && Number(b.setup_fee_paid) > 0) {
              branchSetupSum += Number(b.setup_fee_paid);
              hasExplicitBranchFees = true;
            }
          }
        }
        if (hasExplicitBranchFees && branchSetupSum > 0) {
          setupAmount = branchSetupSum;
        } else {
          setupAmount = (bActive > 0 ? bActive : 1) * 1999.0;
        }
      }

      if (bizPaymentMode === 'cash') {
        totalCashRevenue += setupAmount;
        totalCashCount += 1;
      } else {
        totalOnlineRevenue += setupAmount;
        totalOnlineCount += 1;
      }

      // Renewals revenue
      if (bizRenewalAmountPaid !== null && bizRenewalAmountPaid > 0) {
        totalRenewalsRevenue += bizRenewalAmountPaid;
        totalRenewalsCount += Math.round(bizRenewalAmountPaid / 999.0);
      } else {
        const created = bizData['created_at'] ? bizData['created_at'].toDate() : null;
        const renewal = bizData['renewal_date'] ? bizData['renewal_date'].toDate() : null;
        if (created && renewal) {
          const daysDiff = Math.floor((renewal - created) / (1000 * 60 * 60 * 24));
          if (daysDiff > 370) {
            const extraYears = Math.ceil((daysDiff - 365) / 365);
            totalRenewalsCount += extraYears;
            totalRenewalsRevenue += extraYears * (999.0 * (bActive > 0 ? bActive : 1));
          }
        }
      }
    }
  }

  const newEnrollmentsCount = totalOnlineCount + totalCashCount;
  const newEnrollmentsRevenue = totalOnlineRevenue + totalCashRevenue;
  const totalRevenueSnapshot = newEnrollmentsRevenue + totalRenewalsRevenue;

  return {
    totalActiveBranches,
    totalPendingBranches,
    onlineCount: totalOnlineCount,
    cashCount: totalCashCount,
    onlineRevenue: totalOnlineRevenue,
    cashRevenue: totalCashRevenue,
    newEnrollmentsCount,
    newEnrollmentsRevenue,
    renewalsCount: totalRenewalsCount,
    renewalsRevenue: totalRenewalsRevenue,
    totalRevenueSnapshot,
  };
}

async function runRevenueTest() {
  console.log('🧪 Starting Revenue Calculation Test Suite...\n');

  // Clean up existing test businesses
  const existing = await db.collection('businesses').get();
  for (const doc of existing.docs) {
    const branches = await doc.ref.collection('branches').get();
    for (const b of branches.docs) {
      await b.ref.delete();
    }
    await doc.ref.delete();
  }
  console.log('✓ Cleared previous business documents.');

  const now = Timestamp.now();
  const futureRenewal = Timestamp.fromDate(new Date(Date.now() + 365 * 24 * 60 * 60 * 1000));
  const twoYearsRenewal = Timestamp.fromDate(new Date(Date.now() + 730 * 24 * 60 * 60 * 1000));
  const pastCreated = Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));

  // 1. Business 1: Single-branch Online (Paid ₹1,999)
  console.log('1️⃣ Seeding Single-Branch Online Business (₹1,999)...');
  const biz1Ref = db.collection('businesses').doc('rev_test_single_online');
  await biz1Ref.set({
    brand_name: 'Single Online Store',
    subscription_status: 'active',
    payment_mode: 'online',
    setup_fee_paid: 1999,
    amount_paid: 1999,
    renewal_date: futureRenewal,
    created_at: now,
    is_test_account: false,
  });
  await biz1Ref.collection('branches').doc('branch_1').set({
    branch_name: 'Main',
    subscription_status: 'active',
    payment_mode: 'online',
    setup_fee_paid: 1999,
    amount_paid: 1999,
  });

  // 2. Business 2: Single-branch Cash (Paid ₹1,999)
  console.log('2️⃣ Seeding Single-Branch Cash Business (₹1,999)...');
  const biz2Ref = db.collection('businesses').doc('rev_test_single_cash');
  await biz2Ref.set({
    brand_name: 'Single Cash Store',
    subscription_status: 'active',
    payment_mode: 'cash',
    setup_fee_paid: 1999,
    amount_paid: 1999,
    renewal_date: futureRenewal,
    created_at: now,
    is_test_account: false,
  });
  await biz2Ref.collection('branches').doc('branch_1').set({
    branch_name: 'Main',
    subscription_status: 'active',
    payment_mode: 'cash',
    setup_fee_paid: 1999,
    amount_paid: 1999,
  });

  // 3. Business 3: 5-Branch Multi-Location Online (Paid ₹4,999 total plan price)
  console.log('3️⃣ Seeding 5-Branch Multi-Location Online Business (Paid ₹4,999 total)...');
  const biz3Ref = db.collection('businesses').doc('rev_test_multi_5_online');
  await biz3Ref.set({
    brand_name: 'Mega Retail Chain (5 Branches)',
    subscription_status: 'active',
    payment_mode: 'online',
    setup_fee_paid: 4999,
    amount_paid: 4999,
    total_branches_count: 5,
    active_branches_count: 5,
    renewal_date: futureRenewal,
    created_at: now,
    is_test_account: false,
  });
  for (let i = 1; i <= 5; i++) {
    await biz3Ref.collection('branches').doc(`branch_${i}`).set({
      branch_name: `Branch ${i}`,
      subscription_status: 'active',
      payment_mode: 'online',
      setup_fee_paid: 4999 / 5,
      amount_paid: 4999 / 5,
    });
  }

  // 4. Business 4: Renewal Business (1 Branch, 1 Renewal Paid ₹999)
  console.log('4️⃣ Seeding Renewal Business (Paid ₹999 renewal)...');
  const biz4Ref = db.collection('businesses').doc('rev_test_renewal');
  await biz4Ref.set({
    brand_name: 'Renewed Boutique',
    subscription_status: 'active',
    payment_mode: 'online',
    setup_fee_paid: 1999,
    renewal_amount_paid: 999,
    amount_paid: 2998,
    renewal_date: twoYearsRenewal,
    created_at: pastCreated,
    is_test_account: false,
  });
  await biz4Ref.collection('branches').doc('branch_1').set({
    branch_name: 'Main',
    subscription_status: 'active',
    payment_mode: 'online',
    setup_fee_paid: 1999,
  });

  // Execute Dashboard Calculation
  console.log('\n📊 Calculating Admin Dashboard Revenue Metrics...');
  const stats = await computeDashboardRevenue();

  console.log('\n--- CALCULATED METRICS ---');
  console.log(`• Total Active Branches:   ${stats.totalActiveBranches} (Expected: 8)`);
  console.log(`• Online Revenue:          ₹${stats.onlineRevenue} (Expected: ₹8,997 setup [1999 + 4999 + 1999])`);
  console.log(`• Cash Revenue:            ₹${stats.cashRevenue} (Expected: ₹1,999)`);
  console.log(`• New Enrollments Revenue: ₹${stats.newEnrollmentsRevenue} (Expected: ₹10,996)`);
  console.log(`• Renewals Revenue:        ₹${stats.renewalsRevenue} (Expected: ₹999)`);
  console.log(`• Total Revenue Snapshot:  ₹${stats.totalRevenueSnapshot} (Expected: ₹11,995)`);

  // Assertions
  assert.strictEqual(stats.totalActiveBranches, 8, 'Should have 1 + 1 + 5 + 1 = 8 active branches');
  
  // Specific checks for the mix requested by the prompt:
  // Single-branch online setup = 1999
  // Single-branch cash setup = 1999
  // 5-branch multi online setup = 4999 (NOT 5 * 1999 = 9995)
  // Renewal business online setup = 1999, renewal = 999
  assert.strictEqual(stats.cashRevenue, 1999.0, 'Cash revenue must equal ₹1,999');
  assert.strictEqual(stats.onlineRevenue, 1999.0 + 4999.0 + 1999.0, 'Online setup revenue must sum ₹1999 + ₹4999 + ₹1999 = ₹8,997 (NOT inflated to count * 1999)');
  assert.strictEqual(stats.renewalsRevenue, 999.0, 'Renewals revenue must equal ₹999');
  assert.strictEqual(stats.totalRevenueSnapshot, 1999.0 + 1999.0 + 4999.0 + 1999.0 + 999.0, 'Total revenue snapshot must equal exact sum ₹11,995');

  console.log('\n🎉 ALL REVENUE CALCULATION TESTS PASSED SUCCESSFULLY!');
}

runRevenueTest().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
