#!/usr/bin/env node
// scripts/enroll-brew-bar.js
//
// Enrolls "Brew Bar Cafe" through the SAME Firestore code path as the Flutter
// enrollment form — creates a pending_payment draft (as the form does), then
// activates it to "active" (as the payment webhook would).
//
// This exactly mirrors EnrollProvider.submit() + FirestoreService.enrollBusiness().
//
// Usage:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   node scripts/enroll-brew-bar.js

'use strict';

process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth }                 = require('firebase-admin/auth');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');

if (getApps().length === 0) {
  initializeApp({ projectId: 'review-system-prod-49b7a' });
}

const auth = getAuth();
const db   = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

// ─── FORM DATA (exactly what the employee fills in) ────────────────────────
const FORM = {
  // Business Details
  brandName:    'Brew Bar Cafe',
  categoryType: 'Restaurant',
  templateId:   null,        // no template selected
  logoUrl:      '',          // no logo uploaded

  // Owner Contact
  ownerName:    'Raj Mehta',
  ownerEmail:   'raj.mehta@brewbar.com',
  ownerPhone:   '+919876543210',

  // Branch (single-location mode → branch_name = brand_name automatically)
  branch: {
    branchName:       'Brew Bar Cafe',  // auto-set from brandName in single mode
    whatsappNumber:   '+919876543210',
    address:          '17, Park Street, Kolkata, West Bengal 700016',
    placeId:          '',               // left blank
    googleReviewLink: null,
    starRoutingConfig: {
      '1': 'thankyou',
      '2': 'thankyou',
      '3': 'whatsapp',
      '4': 'google',
      '5': 'google',
    },
  },
};
// ───────────────────────────────────────────────────────────────────────────

async function run() {
  console.log('\n☕  Enrolling "Brew Bar Cafe" via employee form path\n');

  // 1. Resolve employee UID
  let empUid;
  try {
    const user = await auth.getUserByEmail('employee@test.com');
    empUid = user.uid;
    console.log(`  ✅ employee@test.com → uid=${empUid}`);
  } catch (e) {
    console.error('  ❌ employee@test.com not found. Run seed-employee-user.js first.');
    process.exit(1);
  }

  // 2. Atomically create business + branch (identical to enrollBusiness() batch)
  const bizRef    = db.collection('businesses').doc();
  const branchRef = bizRef.collection('branches').doc();
  const batch     = db.batch();

  // Business doc — status = pending_payment (exactly as the form creates it)
  batch.set(bizRef, {
    brand_name:                   FORM.brandName,
    logo_url:                     FORM.logoUrl,
    category_type:                FORM.categoryType,
    default_category_template_id: FORM.templateId,
    enrolled_by:                  empUid,
    enrolled_by_original:         empUid,
    currently_managed_by:         empUid,
    subscription_status:          'pending_payment',  // ← draft state from form
    owner_auth_uid:               null,
    owner_email:                  FORM.ownerEmail,
    owner_name:                   FORM.ownerName,
    owner_phone:                  FORM.ownerPhone,
    created_at:                   Timestamp.now(),
  });

  // Branch doc
  const f = FORM.branch;
  batch.set(branchRef, {
    branch_name:          f.branchName,
    address:              f.address,
    whatsapp_number:      f.whatsappNumber,
    place_id:             f.placeId || null,
    google_review_link:   f.googleReviewLink,
    star_routing_config:  f.starRoutingConfig,
    category_override_id: null,
    qr_code_id:           null,
    nfc_tag_id:           null,
    stats_summary:        { total_scans: 0, total_reviews_redirected: 0 },
  });

  await batch.commit();
  console.log(`  ✅ Draft created: businesses/${bizRef.id}  (status=pending_payment)`);
  console.log(`  ✅ Branch:        businesses/${bizRef.id}/branches/${branchRef.id}`);

  // 3. Activate the draft (simulate payment webhook / activateDraft)
  //    The watchMyBusinesses query excludes pending_payment, so we activate it
  //    so it appears in the dashboard — this is what payment confirmation does.
  const renewalDate = new Date();
  renewalDate.setFullYear(renewalDate.getFullYear() + 1);

  await bizRef.update({
    subscription_status:  'active',
    renewal_date:         Timestamp.fromDate(renewalDate),
  });
  console.log(`  ✅ Activated: status=active, renewal=${renewalDate.toDateString()}`);

  // 4. Update employee counters (incremented on activation, not on draft)
  await db.collection('employees').doc(empUid).update({
    total_enrollments:      FieldValue.increment(1),
    this_month_enrollments: FieldValue.increment(1),
  });
  console.log(`  ✅ Employee counters incremented`);

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('✅  ENROLLMENT COMPLETE');
  console.log('\nForm data entered:');
  console.log('  Business name:  Brew Bar Cafe');
  console.log('  Category:       Restaurant');
  console.log('  Owner name:     Raj Mehta');
  console.log('  Owner email:    raj.mehta@brewbar.com');
  console.log('  Owner phone:    +919876543210');
  console.log('  WhatsApp:       +919876543210');
  console.log('  Address:        17, Park Street, Kolkata, West Bengal 700016');
  console.log('  Place ID:       (blank)');
  console.log('  Star routing:   1★=Thank you, 2★=Thank you, 3★=WhatsApp, 4★=Google, 5★=Google');
  console.log('\nFirestore:');
  console.log('  businesses/' + bizRef.id);
  console.log('  businesses/' + bizRef.id + '/branches/' + branchRef.id);
  console.log('\nLog in as employee@test.com / Test1234! → should show "Brew Bar Cafe" (Active)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

run().catch(err => {
  console.error('❌ Enrollment failed:', err.message);
  process.exit(1);
});
