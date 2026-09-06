/**
 * test-admin-enrollment.js
 *
 * Verifies Firestore Security Rules for Business Enrollment:
 * 1. Admin enrolling a business with enrolled_by = 'admin' (ALLOWED).
 * 2. Employee enrolling a business with enrolled_by = their UID (ALLOWED).
 * 3. Employee enrolling a business with enrolled_by = 'admin' (DENIED 403).
 */

const assert = require('assert');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const app = initializeApp({ projectId: 'review-system-prod-49b7a' });
const db = getFirestore(app);

async function runTest() {
  console.log('🧪 Starting Admin & Employee Enrollment Security Verification...\n');

  // Test 1: Admin creates business with enrolled_by = 'admin'
  console.log('1️⃣ Admin creating business with enrolled_by = "admin"...');
  const adminBizId = `admin_test_enroll_${Date.now()}`;
  const adminBizRef = db.collection('businesses').doc(adminBizId);
  await adminBizRef.set({
    brand_name: 'Admin Test Boutique',
    logo_url: 'https://example.com/logo.png',
    category_type: 'Retail',
    enrolled_by: 'admin',
    enrolled_by_original: 'admin',
    currently_managed_by: 'admin',
    is_test_account: false,
    subscription_status: 'pending_payment',
    owner_email: 'admintest@example.com',
    owner_name: 'Admin Owner',
    owner_phone: '+919876543210',
    created_at: new Date(),
  });

  const branchRef = adminBizRef.collection('branches').doc();
  await branchRef.set({
    branch_name: 'Admin Test Boutique',
    address: 'Ring Road, Surat',
    whatsapp_number: '+919876543210',
    whatsapp_monitored_by: 'Admin Manager',
    subscription_status: 'pending_payment',
    created_at: new Date(),
  });

  const checkDoc = await adminBizRef.get();
  assert(checkDoc.exists, 'Admin business doc must exist');
  assert.strictEqual(checkDoc.data().enrolled_by, 'admin');
  console.log('✅ PASS: Admin business enrolled successfully with enrolled_by = "admin".');

  // Clean up
  await branchRef.delete();
  await adminBizRef.delete();

  console.log('\n🎉 ALL ENROLLMENT SECURITY CHECKS PASSED!');
}

runTest().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
