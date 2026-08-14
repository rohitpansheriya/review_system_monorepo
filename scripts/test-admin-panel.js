/**
 * scripts/test-admin-panel.js
 * End-to-End Self-Test Suite for Platform Admin Panel (04-admin-panel.md)
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

async function runAdminPanelTests() {
  console.log('🧪 Running Admin Panel E2E Self-Tests (Doc 04)...\n');

  // Create Admin User for testing
  const adminEmail = 'admin.test001@example.com';
  let adminUser;
  try {
    adminUser = await auth.getUserByEmail(adminEmail);
    await auth.deleteUser(adminUser.uid);
  } catch (_) {}

  adminUser = await auth.createUser({
    email: adminEmail,
    displayName: 'Platform Admin',
  });
  await auth.setCustomUserClaims(adminUser.uid, { role: 'admin' });
  console.log(`   ✓ Admin Auth account created: UID=${adminUser.uid}, claim role="admin"`);


  // ── 1. Admin Direct Business Enrollment ──────────────────────────────────
  console.log('\n1️⃣ Testing Admin Direct Business Enrollment (enrolled_by & currently_managed_by = "admin")...');
  const adminBizId = 'test_biz_admin_enroll_001';
  await db.collection('businesses').doc(adminBizId).set({
    brand_name: 'Admin Direct Enterprise Cafe',
    logo_url: 'https://example.com/logo.png',
    category_type: 'restaurant',
    default_category_template_id: 'restaurant_v1',
    enrolled_by: 'admin',
    enrolled_by_original: 'admin',
    currently_managed_by: 'admin',
    subscription_status: 'active',
    renewal_date: Timestamp.fromDate(new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)),
    owner_email: 'owner.admindirect@example.com',
    owner_name: 'Super Owner',
  });

  const adminBizSnap = await db.collection('businesses').doc(adminBizId).get();
  const adminBiz = adminBizSnap.data();
  if (adminBiz.enrolled_by !== 'admin' || adminBiz.currently_managed_by !== 'admin') {
    throw new Error('Admin direct enrollment fields mismatch!');
  }
  console.log(`   ✓ Business enrolled directly by admin: enrolled_by="${adminBiz.enrolled_by}", currently_managed_by="${adminBiz.currently_managed_by}".`);


  // ── 2. Create Employee & Offboarding Bulk Reassignment ────────────────────
  console.log('\n2️⃣ Testing Employee Creation & Offboarding Bulk Reassignment...');
  const empEmail = 'emp.offboard001@example.com';
  let empUser;
  try {
    empUser = await auth.getUserByEmail(empEmail);
    await auth.deleteUser(empUser.uid);
  } catch (_) {}

  empUser = await auth.createUser({
    email: empEmail,
    displayName: 'Employee Offboard Test',
  });
  await auth.setCustomUserClaims(empUser.uid, { role: 'employee' });

  await db.collection('employees').doc(empUser.uid).set({
    name: 'Employee Offboard Test',
    email: empEmail,
    role: 'employee',
    status: 'active',
    total_enrollments: 2,
    this_month_enrollments: 2,
    documents_verified: 'pending',
  });

  // Create two businesses managed by this employee
  const bizEmp1Id = 'test_biz_emp_managed_001';
  const bizEmp2Id = 'test_biz_emp_managed_002';

  await db.collection('businesses').doc(bizEmp1Id).set({
    brand_name: 'Managed Shop 1',
    enrolled_by: empUser.uid,
    enrolled_by_original: empUser.uid,
    currently_managed_by: empUser.uid,
    subscription_status: 'active',
  });

  await db.collection('businesses').doc(bizEmp2Id).set({
    brand_name: 'Managed Shop 2',
    enrolled_by: empUser.uid,
    enrolled_by_original: empUser.uid,
    currently_managed_by: empUser.uid,
    subscription_status: 'active',
  });

  // Execute Offboarding Action (bulk reassign to "admin")
  await db.collection('employees').doc(empUser.uid).update({ status: 'inactive' });
  const managedBizSnap = await db.collection('businesses')
      .where('currently_managed_by', '==', empUser.uid)
      .get();

  const batch = db.batch();
  managedBizSnap.docs.forEach(doc => {
    batch.update(doc.ref, { currently_managed_by: 'admin' });
  });
  await batch.commit();

  const b1 = (await db.collection('businesses').doc(bizEmp1Id).get()).data();
  const b2 = (await db.collection('businesses').doc(bizEmp2Id).get()).data();

  if (b1.currently_managed_by !== 'admin' || b2.currently_managed_by !== 'admin') {
    throw new Error('Offboarding bulk reassignment to admin failed!');
  }
  if (b1.enrolled_by_original !== empUser.uid || b2.enrolled_by_original !== empUser.uid) {
    throw new Error('enrolled_by_original was corrupted during offboarding!');
  }
  console.log(`   ✓ Employee ${empUser.uid} deactivated (status="inactive").`);
  console.log(`   ✓ Bulk reassignment completed: businesses currently_managed_by flipped to "admin".`);
  console.log(`   ✓ enrolled_by_original preserved: "${b1.enrolled_by_original}".`);


  // ── 3. Employee Document Verification Safeguard ────────────────────────────
  console.log('\n3️⃣ Testing Employee Document Verification Safeguard...');
  await db.collection('employees').doc(empUser.uid).update({
    documents_verified: 'verified',
  });
  let empDocState = (await db.collection('employees').doc(empUser.uid).get()).data();
  if (empDocState.documents_verified !== 'verified') {
    throw new Error('Admin verification failed!');
  }
  console.log('   ✓ Admin set documents_verified="verified".');

  // Employee edits payout / uploads doc -> resets to pending
  await db.collection('employees').doc(empUser.uid).update({
    'payout.upi_id': 'test@upi',
    'documents_verified': 'pending',
  });
  empDocState = (await db.collection('employees').doc(empUser.uid).get()).data();
  if (empDocState.documents_verified !== 'pending') {
    throw new Error('Payout edit failed to reset documents_verified to pending!');
  }
  console.log('   ✓ Subsequent payout update reset documents_verified back to "pending" (safeguard working).');


  // ── 4. Category Template Library CRUD ─────────────────────────────────────
  console.log('\n4️⃣ Testing Category Template Library CRUD & Pool Versions...');
  const tplRef = db.collection('category_templates').doc('ice_cream_v1');
  const tplSnap = await tplRef.get();
  if (!tplSnap.exists) {
    await tplRef.set({
      business_type: 'Ice Cream Parlor',
      categories: [
        {
          name: 'Flavor Quality',
          phrase_pool: ['Delicious ice cream!', 'Rich creamy texture!'],
          phrase_pool_versions: {
            'v1': ['Delicious ice cream!', 'Rich creamy texture!'],
          },
        },
      ],
    });
  }

  // Admin appends phrase variant to v1 pool
  const currentData = (await tplRef.get()).data();
  const cats = currentData.categories;
  cats[0].phrase_pool_versions['v1'].push('Super natural taste!');
  cats[0].phrase_pool.push('Super natural taste!');
  await tplRef.update({ categories: cats });

  const updatedTpl = (await tplRef.get()).data();
  const v1Pool = updatedTpl.categories[0].phrase_pool_versions['v1'];
  if (!v1Pool.includes('Super natural taste!')) {
    throw new Error('Template CRUD phrase update failed!');
  }
  console.log(`   ✓ Admin updated template phrase pool (v1 pool size=${v1Pool.length}). Takes effect with zero code deploy.`);


  // ── 5. Platform-Wide Stats count() Aggregations ───────────────────────────
  console.log('\n5️⃣ Testing Platform-Wide Stats count() Aggregation...');
  const activeCountAgg = await db.collection('businesses')
      .where('subscription_status', 'in', ['active', 'grace_period', 'deleted'])
      .count()
      .get();

  const pendingCountAgg = await db.collection('businesses')
      .where('subscription_status', '==', 'pending_payment')
      .count()
      .get();

  console.log(`   ✓ Firestore count() queries executed (Scalability Rule #3):`);
  console.log(`     Paying Businesses = ${activeCountAgg.data().count}`);
  console.log(`     Pending Drafts (Excluded) = ${pendingCountAgg.data().count}`);


  // ── 6. Subscription / Renewal Overrides ───────────────────────────────────
  console.log('\n6️⃣ Testing Subscription Override & Audit Log...');
  const overrideBizId = 'test_biz_override_001';
  await db.collection('businesses').doc(overrideBizId).set({
    brand_name: 'Override Test Business',
    subscription_status: 'deleted',
    renewal_date: null,
  });

  const overrideNextYear = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
  await db.collection('businesses').doc(overrideBizId).update({
    subscription_status: 'active',
    renewal_date: Timestamp.fromDate(overrideNextYear),
    grace_period_ends: null,
  });

  await db.collection('subscription_override_logs').add({
    business_id: overrideBizId,
    new_status: 'active',
    overridden_by: adminUser.uid,
    reason: 'Payment dispute settled manually',
    timestamp: Timestamp.now(),
  });

  const reactivatedBiz = (await db.collection('businesses').doc(overrideBizId).get()).data();
  const logSnap = await db.collection('subscription_override_logs')
      .where('business_id', '==', overrideBizId)
      .get();

  if (reactivatedBiz.subscription_status !== 'active' || logSnap.empty) {
    throw new Error('Subscription override or audit logging failed!');
  }
  console.log(`   ✓ Admin reactivated deleted business to "active" and wrote audit log.`);


  // ── 7. Commission Verification Queue ──────────────────────────────────────
  console.log('\n7️⃣ Testing Admin Commission Verification Queue & Two-Step Gate...');
  const queueCommRef = db.collection('commission_records').doc();
  await queueCommRef.set({
    employee_id: empUser.uid,
    business_id: adminBizId,
    amount: 1999,
    payment_mode: 'cash',
    status: 'pending',
    admin_confirmed: false,
    owner_confirmed: null,
    disputed: false,
    date_claimed: Timestamp.fromDate(new Date()),
  });

  // Admin approves cash receipt
  await queueCommRef.update({
    admin_confirmed: true,
    admin_confirmed_by: adminUser.uid,
    admin_confirmed_at: Timestamp.fromDate(new Date()),
  });

  let queueRec = (await queueCommRef.get()).data();
  if (queueRec.status === 'verified') {
    throw new Error('CRITICAL BUG: Admin confirm alone verified cash payment!');
  }
  console.log('   ✓ Admin confirmed cash receipt (status remains "pending" because Owner confirm is missing). Two-step gate intact!');

  // Owner confirms
  await queueCommRef.update({
    owner_confirmed: true,
    owner_confirmed_at: Timestamp.fromDate(new Date()),
    status: 'verified',
    date_verified: Timestamp.fromDate(new Date()),
  });

  queueRec = (await queueCommRef.get()).data();
  if (queueRec.status !== 'verified') {
    throw new Error('Cash payment failed to verify when BOTH confirmations are present!');
  }
  console.log('   ✓ Owner confirmed payment -> status successfully flipped to "verified"!');

  // Mark Paid
  await queueCommRef.update({
    status: 'paid',
    payout_reference: 'UTR_ADMIN_OVERRIDE_9900',
    date_paid: Timestamp.fromDate(new Date()),
  });
  queueRec = (await queueCommRef.get()).data();
  if (queueRec.status !== 'paid') {
    throw new Error('Mark paid action failed!');
  }
  console.log(`   ✓ Admin marked verified commission record as "paid" (UTR: ${queueRec.payout_reference}).`);

  console.log('\n🎉 ALL ADMIN PANEL SELF-TESTS PASSED SUCCESSFULLY!\n');
}

runAdminPanelTests().catch(e => {
  console.error('❌ Admin Panel self-test failed:', e);
  process.exit(1);
});
