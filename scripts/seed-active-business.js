#!/usr/bin/env node
// scripts/seed-active-business.js
//
// Creates ONE active business (subscription_status = "active") owned by
// employee@test.com so the My Enrolled Businesses screen shows it.
//
// Run AFTER the emulators are up and employee@test.com has been seeded:
//
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   node scripts/seed-active-business.js

'use strict';

process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth }                 = require('firebase-admin/auth');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

if (getApps().length === 0) {
  initializeApp({ projectId: 'review-system-prod-49b7a' });
}

const auth = getAuth();
const db   = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

async function run() {
  console.log('\n🌱 seed-active-business.js\n');

  // 1. Resolve employee UID
  let empUid;
  try {
    const user = await auth.getUserByEmail('employee@test.com');
    empUid = user.uid;
    console.log('  ✅ Found employee@test.com  uid=' + empUid);
  } catch (e) {
    console.error(
      '  ❌ employee@test.com not found in Auth emulator.',
      '\n     Run:  node scripts/seed-employee-user.js  first.',
    );
    process.exit(1);
  }

  // 2. Ensure employees/{uid} doc exists with counter = 1
  await db.collection('employees').doc(empUid).set(
    {
      name:                   'Test Employee',
      contact:                'employee@test.com',
      role:                   'employee',
      active:                 true,
      total_enrollments:      1,
      this_month_enrollments: 1,
    },
    { merge: true },
  );
  console.log('  ✅ employees/' + empUid + ' doc ensured');

  // 3. Create the active business
  const BIZ_ID    = 'seed-active-biz-001';
  const BRANCH_ID = 'seed-active-branch-001';

  const renewalDate = new Date();
  renewalDate.setFullYear(renewalDate.getFullYear() + 1);

  const batch = db.batch();

  const bizRef = db.collection('businesses').doc(BIZ_ID);
  batch.set(bizRef, {
    brand_name:                   'Demo Cafe',
    logo_url:                     '',
    category_type:                'Restaurant',
    default_category_template_id: null,
    enrolled_by:                  empUid,
    enrolled_by_original:         empUid,
    currently_managed_by:         empUid,
    subscription_status:          'active',
    renewal_date:                 Timestamp.fromDate(renewalDate),
    owner_auth_uid:               null,
    owner_email:                  'owner.democafe@test.com',
    owner_name:                   'Demo Owner',
    owner_phone:                  '+919876543210',
    created_at:                   Timestamp.now(),
  }, { merge: true });

  const branchRef = bizRef.collection('branches').doc(BRANCH_ID);
  batch.set(branchRef, {
    branch_name:          'Main Branch',
    address:              '42, MG Road, Ahmedabad, Gujarat 380001',
    whatsapp_number:      '+919876543210',
    place_id:             'ChIJplace-demo-cafe-001',
    google_review_link:   null,
    star_routing_config:  {
      '1': 'thankyou',
      '2': 'thankyou',
      '3': 'whatsapp',
      '4': 'google',
      '5': 'google',
    },
    category_override_id: null,
    qr_code_id:           null,
    nfc_tag_id:           null,
    stats_summary:        { total_scans: 0, total_reviews_redirected: 0 },
  }, { merge: true });

  await batch.commit();
  console.log('  ✅ businesses/' + BIZ_ID + '  (status=active, enrolled_by=' + empUid + ')');
  console.log('  ✅ businesses/' + BIZ_ID + '/branches/' + BRANCH_ID);

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('✅  Done. Log in to the Flutter panel as:');
  console.log('    Email:    employee@test.com');
  console.log('    Password: Test1234!');
  console.log('    → My Enrolled Businesses should show "Demo Cafe" (Active)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

run().catch(err => {
  console.error('❌ seed-active-business.js failed:', err);
  process.exit(1);
});
