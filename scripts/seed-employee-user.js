#!/usr/bin/env node
// scripts/seed-employee-user.js
// Creates a test employee user in the Firebase Auth emulator and their
// employees/{uid} document in Firestore.
//
// Usage:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   node scripts/seed-employee-user.js
//
// The employee can then sign in at the Flutter panel with:
//   Email: employee@test.com  Password: Test1234!
//
// A second non-employee user is also created to test access-denied rejection.

const { initializeApp } = require('firebase-admin/app');
const { getAuth }       = require('firebase-admin/auth');
const { getFirestore, Timestamp }  = require('firebase-admin/firestore');

process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST     = process.env.FIRESTORE_EMULATOR_HOST     || '127.0.0.1:8080';

initializeApp({ projectId: 'review-system-prod-49b7a' });
const auth = getAuth();
const db   = getFirestore();

async function run() {
  // ── 0. Admin user ───────────────────────────────────────────────────────────
  let adminUid;
  try {
    const existing = await auth.getUserByEmail('admin@test.com');
    adminUid = existing.uid;
    console.log(`  ℹ️  Admin user already exists: ${adminUid}`);
  } catch (_) {
    const user = await auth.createUser({
      email:       'admin@test.com',
      password:    'Test1234!',
      displayName: 'Platform Admin',
    });
    adminUid = user.uid;
    console.log(`  ✅ Created admin user: ${adminUid}`);
  }
  await auth.setCustomUserClaims(adminUid, { role: 'admin' });
  console.log(`  ✅ Set custom claim role=admin on ${adminUid}`);

  // ── 1. Employee user ────────────────────────────────────────────────────────
  let empUid;
  try {
    const existing = await auth.getUserByEmail('employee@test.com');
    empUid = existing.uid;
    console.log(`  ℹ️  Employee user already exists: ${empUid}`);
  } catch (_) {
    const user = await auth.createUser({
      email:    'employee@test.com',
      password: 'Test1234!',
      displayName: 'Test Employee',
    });
    empUid = user.uid;
    console.log(`  ✅ Created employee user: ${empUid}`);
  }

  // Set custom claim role=employee
  await auth.setCustomUserClaims(empUid, { role: 'employee' });
  console.log(`  ✅ Set custom claim role=employee on ${empUid}`);

  // Create employees/{uid} doc
  await db.collection('employees').doc(empUid).set({
    name:                   'Test Employee',
    contact:                'employee@test.com',
    role:                   'employee',
    active:                 true,
    total_enrollments:      0,
    this_month_enrollments: 0,
  }, { merge: true });
  console.log(`  ✅ employees/${empUid} doc created/updated`);

  // ── 2. Employee B (for cross-employee access control test) ──────────────────
  let empBUid;
  try {
    const existing = await auth.getUserByEmail('employee.b@test.com');
    empBUid = existing.uid;
    console.log(`\n  ℹ️  Employee B already exists: ${empBUid}`);
  } catch (_) {
    const user = await auth.createUser({
      email:    'employee.b@test.com',
      password: 'Test1234!',
      displayName: 'Employee B',
    });
    empBUid = user.uid;
    console.log(`\n  ✅ Created employee B: ${empBUid}`);
  }
  await auth.setCustomUserClaims(empBUid, { role: 'employee' });
  await db.collection('employees').doc(empBUid).set({
    name:                   'Employee B',
    contact:                'employee.b@test.com',
    role:                   'employee',
    active:                 true,
    total_enrollments:      0,
    this_month_enrollments: 0,
  }, { merge: true });
  console.log(`  ✅ employees/${empBUid} doc created/updated`);

  // Create a business owned by Employee B
  const bizRef = db.collection('businesses').doc('biz-owned-by-emp-b');
  await bizRef.set({
    brand_name:                   'Employee B Shop',
    logo_url:                     '',
    category_type:                'Retail',
    default_category_template_id: null,
    enrolled_by:                  empBUid,
    enrolled_by_original:         empBUid,
    currently_managed_by:         empBUid,
    subscription_status:          'active',
    renewal_date:                 Timestamp.fromDate(new Date(Date.now() + 365 * 86400000)),
    grace_period_ends:            null,
    owner_auth_uid:               null,
    owner_email:                  'owner.b@test.com',
  }, { merge: true });
  await bizRef.collection('branches').doc('branch-b-001').set({
    branch_name:          'Main Branch B',
    address:              '1 Test Street',
    whatsapp_number:      '+910000000001',
    place_id:             'ChIJplace-b-001',
    google_review_link:   null,
    star_routing_config:  { '1': 'thankyou', '2': 'thankyou', '3': 'whatsapp', '4': 'google', '5': 'google' },
    category_override_id: null,
    qr_code_id:           null,
    nfc_tag_id:           null,
    stats_summary:        { total_scans: 0, total_reviews_redirected: 0 },
  }, { merge: true });
  console.log(`  ✅ Created test business for Employee B (used in T-E6 cross-access test)`);

  // ── 3. Non-employee user (for T-E8: access-denied test) ─────────────────────
  let ownerUid;
  try {
    const existing = await auth.getUserByEmail('owner@test.com');
    ownerUid = existing.uid;
    console.log(`\n  ℹ️  Owner test user already exists: ${ownerUid}`);
  } catch (_) {
    const user = await auth.createUser({
      email:    'owner@test.com',
      password: 'Test1234!',
      displayName: 'Test Owner',
    });
    ownerUid = user.uid;
    console.log(`\n  ✅ Created owner test user: ${ownerUid}`);
  }
  await auth.setCustomUserClaims(ownerUid, { role: 'owner' });
  console.log(`  ✅ Set custom claim role=owner (should be rejected by Flutter panel)`);

  // ── Summary ─────────────────────────────────────────────────────────────────
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('✅  Seed complete. Use these credentials in the Flutter panel:\n');
  console.log('  Admin User (Full Platform Admin Access):');
  console.log('    Email:    admin@test.com');
  console.log('    Password: Test1234!');
  console.log('    UID:     ', adminUid);
  console.log('');
  console.log('  Employee A (Employee Dashboard Access):');
  console.log('    Email:    employee@test.com');
  console.log('    Password: Test1234!');
  console.log('    UID:     ', empUid);
  console.log('');
  console.log('  Employee B (cross-access test):');
  console.log('    Email:    employee.b@test.com');
  console.log('    Password: Test1234!');
  console.log('    UID:     ', empBUid);
  console.log('    Owns:     biz-owned-by-emp-b  (Employee A must NOT see this)');
  console.log('');
  console.log('  Owner (Owner Dashboard Access):');
  console.log('    Email:    owner@test.com');
  console.log('    Password: Test1234!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

run().catch(console.error);
