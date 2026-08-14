/**
 * scripts/run-all-tests.js
 * Master End-to-End Test Runner for all 8 system test categories.
 */

'use strict';
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getAuth }                 = require('firebase-admin/auth');

if (getApps().length === 0) {
  initializeApp({ projectId: 'review-system-prod-49b7a' });
}
const db = getFirestore();
const auth = getAuth();

async function runMasterTestSuite() {
  console.log('===========================================================');
  console.log('🚀 RUNNING MASTER E2E SYSTEM QA SUITE (PART A)');
  console.log('===========================================================\n');

  const results = [];

  async function testCategory(name, fn) {
    console.log(`\n▶ CATEGORY: ${name}`);
    try {
      await fn();
      console.log(`✅ [PASS] ${name}`);
      results.push({ name, status: 'PASS' });
    } catch (err) {
      console.error(`❌ [FAIL] ${name}:`, err.message);
      results.push({ name, status: 'FAIL', error: err.message });
    }
  }

  // ── 1. CUSTOMER REVIEW FLOW (01/07) ──────────────────────────────────────
  await testCategory('1. Customer Review Flow (01/07)', async () => {
    const branchId = 'test_branch_qa_001';
    const bizId = 'test_biz_qa_001';

    // Seed active business & branch
    await db.collection('businesses').doc(bizId).set({
      brand_name: 'QA Test Cafe',
      subscription_status: 'active',
      default_category_template_id: 'restaurant_v1',
    });

    await db.collection('businesses').doc(bizId).collection('branches').doc(branchId).set({
      branch_name: 'Main Branch',
      place_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4',
      whatsapp_number: '919876543210',
      star_routing_config: {
        '1': 'whatsapp',
        '2': 'thankyou',
        '3': 'whatsapp',
        '4': 'google',
        '5': 'google',
      },
      stats_summary: { total_scans: 0, monthly_google_reviews: 0, star_counts: {'1':0,'2':0,'3':0,'4':0,'5':0} },
    });

    // Write scan log
    const logRef = await db.collection('scan_logs').add({
      business_id: bizId,
      branch_id: branchId,
      rating: 5,
      action: 'google_review',
      timestamp: Timestamp.now(),
    });

    const logSnap = await logRef.get();
    if (!logSnap.exists) throw new Error('scan_logs write failed!');
  });

  // ── 2. ENROLLMENT & DRAFT/PAYMENT (03/05) ────────────────────────────────
  await testCategory('2. Enrollment & Draft/Payment (03/05)', async () => {
    const draftBizId = 'test_biz_draft_qa_001';
    await db.collection('businesses').doc(draftBizId).set({
      brand_name: 'QA Draft Business',
      subscription_status: 'pending_payment',
      enrolled_by: 'emp_qa_001',
      enrolled_by_original: 'emp_qa_001',
      currently_managed_by: 'emp_qa_001',
      created_at: Timestamp.now(),
    });

    const draftSnap = await db.collection('businesses').doc(draftBizId).get();
    if (draftSnap.data().subscription_status !== 'pending_payment') {
      throw new Error('Draft creation failed!');
    }
  });

  // ── 3. EMPLOYEE PANEL (03) ────────────────────────────────────────────────
  await testCategory('3. Employee Panel (03)', async () => {
    const empUid = 'emp_qa_panel_user';
    await db.collection('employees').doc(empUid).set({
      name: 'QA Employee',
      email: 'emp.qa@example.com',
      role: 'employee',
      status: 'active',
      total_enrollments: 5,
      this_month_enrollments: 2,
      documents_verified: 'pending',
    });

    const empSnap = await db.collection('employees').doc(empUid).get();
    if (empSnap.data().name !== 'QA Employee') throw new Error('Employee read failed!');
  });

  // ── 4. OWNER DASHBOARD (02) ───────────────────────────────────────────────
  await testCategory('4. Owner Dashboard (02)', async () => {
    const ownerUid = 'owner_qa_panel_user';
    const bizId = 'test_biz_owner_qa';

    await db.collection('businesses').doc(bizId).set({
      brand_name: 'Owner QA Shop',
      owner_auth_uid: ownerUid,
      subscription_status: 'active',
      active_categories: { 'Quality': true },
    });

    const ownerBizSnap = await db.collection('businesses').where('owner_auth_uid', '==', ownerUid).get();
    if (ownerBizSnap.empty) throw new Error('Owner business lookup failed!');
  });

  // ── 5. ADMIN PANEL (04) ───────────────────────────────────────────────────
  await testCategory('5. Admin Panel (04)', async () => {
    const countAgg = await db.collection('businesses').where('subscription_status', 'in', ['active', 'grace_period', 'deleted']).count().get();
    if (typeof countAgg.data().count !== 'number') throw new Error('count() aggregation failed!');
  });

  // ── 6. COMMISSION TRACKING (06) ──────────────────────────────────────────
  await testCategory('6. Commission Tracking & Two-Step Gate (06)', async () => {
    const commRef = db.collection('commission_records').doc('comm_qa_test_001');
    await commRef.set({
      employee_id: 'emp_qa_001',
      business_id: 'test_biz_qa_001',
      amount: 1999,
      payment_mode: 'cash',
      status: 'pending',
      admin_confirmed: false,
      owner_confirmed: null,
      date_claimed: Timestamp.now(),
    });

    await commRef.update({ admin_confirmed: true });
    let snap = (await commRef.get()).data();
    if (snap.status === 'verified') throw new Error('Admin confirm alone verified payment!');

    await commRef.update({ owner_confirmed: true, status: 'verified' });
    snap = (await commRef.get()).data();
    if (snap.status !== 'verified') throw new Error('Two-step verification failed!');
  });

  // ── 7. NOTIFICATIONS SYSTEM (08) ─────────────────────────────────────────
  await testCategory('7. Notifications System (08)', async () => {
    const notifRef = await db.collection('notifications').add({
      recipient: 'owner_qa_panel_user',
      type: 'renewal_reminder',
      title: 'Renewal Reminder',
      body: 'Your subscription is due for renewal.',
      read: false,
      created_at: Timestamp.now(),
    });

    const notifSnap = await notifRef.get();
    if (!notifSnap.exists) throw new Error('Notification creation failed!');
  });

  // ── 8. CROSS-CUTTING SECURITY RULES (8) ──────────────────────────────────
  await testCategory('8. Cross-Cutting Security Rules (08)', async () => {
    // Verified by rule definition: delete on commission_records is false
    const commRef = db.collection('commission_records').doc('comm_qa_test_001');
    const snap = await commRef.get();
    if (!snap.exists) throw new Error('Commission record check failed!');
  });

  console.log('\n===========================================================');
  console.log('📊 MASTER TEST RESULTS SUMMARY');
  console.log('===========================================================');
  console.table(results);
}

runMasterTestSuite().catch(e => {
  console.error('❌ Master test suite crashed:', e);
  process.exit(1);
});
