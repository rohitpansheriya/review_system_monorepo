#!/usr/bin/env node
// scripts/restore-sonal-bhel.js
//
// Re-creates and activates "Sonal Bhel" with the exact original IDs:
//   Business ID: 9bbGsyvvWVWVVsCjMSJ2
//   Branch ID:   B3jSgqOS99BXRCMNgNqB
//
// URL: https://appnexa.co.in/r/9bbGsyvvWVWVVsCjMSJ2/B3jSgqOS99BXRCMNgNqB
//
// Usage:
//   node scripts/restore-sonal-bhel.js
// Or against emulator:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/restore-sonal-bhel.js

'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth }                 = require('firebase-admin/auth');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

if (getApps().length === 0) {
  initializeApp({ projectId: 'review-system-prod-49b7a' });
}

const auth = getAuth();
const db   = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

const BIZ_ID      = '9bbGsyvvWVWVVsCjMSJ2';
const BRANCH_ID   = 'B3jSgqOS99BXRCMNgNqB';
const BRAND_NAME  = 'Sonal Bhel';
const OWNER_NAME  = 'Sonal Bhel';
const OWNER_PHONE = '+919726222216';
const OWNER_EMAIL = 'shreykapuriya4807@gmail.com';
const GOOGLE_LINK = 'https://search.google.com/local/writereview?placeid=ChIJ6zze0RpP4DsR_bhCFb0s2Hk';
const PLACE_ID    = 'ChIJ6zze0RpP4DsR_bhCFb0s2Hk';

async function run() {
  console.log('\n🚀 Restoring "Sonal Bhel" with exact target IDs...\n');
  console.log(`  Target Business ID: ${BIZ_ID}`);
  console.log(`  Target Branch ID:   ${BRANCH_ID}`);

  // 1. Create or resolve Owner Auth user
  let ownerUid;
  try {
    const existing = await auth.getUserByEmail(OWNER_EMAIL);
    ownerUid = existing.uid;
    console.log(`  ✅ Existing auth user found: uid=${ownerUid}`);
  } catch {
    const newUser = await auth.createUser({
      email: OWNER_EMAIL,
      displayName: OWNER_NAME,
      phoneNumber: OWNER_PHONE,
    });
    ownerUid = newUser.uid;
    console.log(`  ✅ New auth user created: uid=${ownerUid}`);
  }

  // Set owner role claim
  await auth.setCustomUserClaims(ownerUid, { role: 'owner' });
  console.log('  ✅ Set custom claim role="owner"');

  // Ensure users/{uid} document exists
  await db.collection('users').doc(ownerUid).set({
    email: OWNER_EMAIL,
    role: 'owner',
    business_id: BIZ_ID,
    name: OWNER_NAME,
    phone: OWNER_PHONE,
    created_at: Timestamp.now(),
  }, { merge: true });
  console.log(`  ✅ users/${ownerUid} document ensured`);

  // 2. Set Business Document
  const renewalDate = new Date();
  renewalDate.setFullYear(renewalDate.getFullYear() + 1);

  const bizRef = db.collection('businesses').doc(BIZ_ID);
  await bizRef.set({
    brand_name:                   BRAND_NAME,
    logo_url:                     '',
    category_type:                'Food & Beverage',
    default_category_template_id: 'ice_cream_v1',
    subscription_status:          'active',
    renewal_date:                 Timestamp.fromDate(renewalDate),
    owner_auth_uid:               ownerUid,
    owner_email:                  OWNER_EMAIL,
    owner_name:                   OWNER_NAME,
    owner_phone:                  OWNER_PHONE,
    created_at:                   Timestamp.now(),
    activated_at:                 Timestamp.now(),
    payment_mode:                 'online',
    total_setup_fee_paid:         1999,
  }, { merge: true });
  console.log(`  ✅ businesses/${BIZ_ID} document created & active`);

  // 3. Set Branch Subdocument
  const branchRef = bizRef.collection('branches').doc(BRANCH_ID);
  await branchRef.set({
    branch_name:          BRAND_NAME,
    address:              'Sonal Bhel',
    whatsapp_number:      OWNER_PHONE,
    place_id:             PLACE_ID,
    google_review_link:   GOOGLE_LINK,
    subscription_status:  'active',
    setup_fee_paid:       1999,
    amount_paid:          1999,
    standee_status:       'delivered',
    star_routing_config: {
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
    created_at:           Timestamp.now(),
    activated_at:         Timestamp.now(),
  }, { merge: true });
  console.log(`  ✅ businesses/${BIZ_ID}/branches/${BRANCH_ID} subdocument created & active`);

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🎉 RESTORATION COMPLETE!');
  console.log(`👉 Review URL: https://appnexa.co.in/r/${BIZ_ID}/${BRANCH_ID}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

run().catch((err) => {
  console.error('❌ Restoration failed:', err);
  process.exit(1);
});
