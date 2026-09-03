/**
 * scripts/seed-9-lifecycle-businesses.js
 *
 * 1. Resets Firestore transactional data (businesses, branches, scans, commissions, notifications).
 * 2. Resets Storage files (logos/, qr_codes/).
 * 3. Deletes old test owner Firebase Auth accounts.
 * 4. Seeds 9 realistic businesses covering all 9 lifecycle test conditions:
 *    1. 30 days before grace (Active, renewal +30d) - APT-01001
 *    2. 15 days before grace (Active, renewal +15d) - APT-01002
 *    3. 7 days before grace (Active, renewal +7d)   - APT-01003
 *    4. 1 day before grace (Active, renewal +1d)    - APT-01004
 *    5. 0 days before grace (Active, renewal 0d)    - APT-01005
 *    6. 1 day in grace (Grace, renewal -1d, grace_ends +29d) - APT-01006
 *    7. 7 days in grace (Grace, renewal -7d, grace_ends +23d) - APT-01007
 *    8. 15 days in grace (Grace, renewal -15d, grace_ends +15d) - APT-01008
 *    9. 30 days in grace (Grace, renewal -30d, grace_ends 0d) - APT-01009
 * 5. Creates Firebase Auth owner accounts with password "AppNexa@2026".
 * 6. Updates `counters/business_counter` to 1009.
 */

'use strict';

const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const QRCode = require('../functions/node_modules/qrcode');
const path = require('path');
const fs = require('fs');

const PROJECT_ID = 'review-system-prod-49b7a';
const BUCKET_NAME = 'review-system-prod-49b7a.firebasestorage.app';
const serviceKeyPath = path.resolve(__dirname, '..', 'serviceAccountKey.json');

if (getApps().length === 0) {
  if (fs.existsSync(serviceKeyPath)) {
    initializeApp({
      credential: cert(serviceKeyPath),
      projectId: PROJECT_ID,
      storageBucket: BUCKET_NAME,
    });
  } else {
    initializeApp({
      projectId: PROJECT_ID,
      storageBucket: BUCKET_NAME,
    });
  }
}

const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });
const auth = getAuth();
const bucket = getStorage().bucket();

const DAY_MS = 86400 * 1000;
const OWNER_PASSWORD = 'AppNexa@2026';

function addDays(date, days) {
  const d = new Date(date);
  d.setTime(d.getTime() + days * DAY_MS);
  return d;
}

const BUSINESS_DEFS = [
  {
    num: 1001,
    code: 'APT-01001',
    brandName: 'The Belgian Waffle Co.',
    categoryType: 'Cafe / Desserts',
    templateId: 'ice_cream_v1',
    ownerName: 'Aarav Patel',
    ownerEmail: 'owner.waffle@appnexa.com',
    ownerPhone: '+919876543210',
    city: 'Ahmedabad',
    address: 'Shop 4, Ground Floor, Alpha One Mall, Vastrapur, Ahmedabad, Gujarat 380015',
    googleReviewLink: 'https://maps.app.goo.gl/waffle123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY4',
    status: 'active',
    daysBeforeGrace: 30, // Condition 1: 30 days before grace
    renewalDeltaDays: 30,
    graceDeltaDays: null,
    totalScans: 340,
    reviewsBoosted: 295,
  },
  {
    num: 1002,
    code: 'APT-01002',
    brandName: 'Toni & Guy Unisex Salon',
    categoryType: 'Salon & Spa',
    templateId: 'salon_v1',
    ownerName: 'Pooja Sharma',
    ownerEmail: 'owner.salon@appnexa.com',
    ownerPhone: '+919876543211',
    city: 'Mumbai',
    address: 'Plot 42, Linking Road, Bandra West, Mumbai, Maharashtra 400050',
    googleReviewLink: 'https://maps.app.goo.gl/toni123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY5',
    status: 'active',
    daysBeforeGrace: 15, // Condition 2: 15 days before grace
    renewalDeltaDays: 15,
    graceDeltaDays: null,
    totalScans: 480,
    reviewsBoosted: 410,
  },
  {
    num: 1003,
    code: 'APT-01003',
    brandName: 'Chai Sutta Bar',
    categoryType: 'Cafe',
    templateId: 'restaurant_v1',
    ownerName: 'Kunal Verma',
    ownerEmail: 'owner.chai@appnexa.com',
    ownerPhone: '+919876543212',
    city: 'Indore',
    address: '12 Bhawarkua Main Road, Near IT Park, Indore, MP 452001',
    googleReviewLink: 'https://maps.app.goo.gl/chai123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY6',
    status: 'active',
    daysBeforeGrace: 7, // Condition 3: 7 days before grace
    renewalDeltaDays: 7,
    graceDeltaDays: null,
    totalScans: 620,
    reviewsBoosted: 540,
  },
  {
    num: 1004,
    code: 'APT-01004',
    brandName: 'Gordhan Thal Gujarati Dining',
    categoryType: 'Restaurant',
    templateId: 'restaurant_v1',
    ownerName: 'Ramesh Gordhan',
    ownerEmail: 'owner.thal@appnexa.com',
    ownerPhone: '+919876543213',
    city: 'Surat',
    address: 'Ring Road, Near Surat Railway Station, Surat, Gujarat 395002',
    googleReviewLink: 'https://maps.app.goo.gl/thal123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY7',
    status: 'active',
    daysBeforeGrace: 1, // Condition 4: 1 day before grace
    renewalDeltaDays: 1,
    graceDeltaDays: null,
    totalScans: 510,
    reviewsBoosted: 440,
  },
  {
    num: 1005,
    code: 'APT-01005',
    brandName: 'Havmor Ice Cream Lounge',
    categoryType: 'Ice Cream Parlour',
    templateId: 'ice_cream_v1',
    ownerName: 'Jatin Choksi',
    ownerEmail: 'owner.havmor@appnexa.com',
    ownerPhone: '+919876543214',
    city: 'Ahmedabad',
    address: 'Navrangpura, CG Road, Ahmedabad, Gujarat 380009',
    googleReviewLink: 'https://maps.app.goo.gl/havmor123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY8',
    status: 'active',
    daysBeforeGrace: 0, // Condition 5: 0 days before grace (due today)
    renewalDeltaDays: 0,
    graceDeltaDays: null,
    totalScans: 720,
    reviewsBoosted: 630,
  },
  {
    num: 1006,
    code: 'APT-01006',
    brandName: 'Subway Fresh Sandwiches',
    categoryType: 'Restaurant',
    templateId: 'restaurant_v1',
    ownerName: 'Vikram Singh',
    ownerEmail: 'owner.subway@appnexa.com',
    ownerPhone: '+919876543215',
    city: 'Pune',
    address: 'FC Road, Deccan Gymkhana, Pune, Maharashtra 411004',
    googleReviewLink: 'https://maps.app.goo.gl/subway123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY9',
    status: 'grace_period',
    daysInGrace: 1, // Condition 6: 1 day in grace (renewal -1d, grace ends +29d)
    renewalDeltaDays: -1,
    graceDeltaDays: 29,
    totalScans: 280,
    reviewsBoosted: 240,
  },
  {
    num: 1007,
    code: 'APT-01007',
    brandName: 'Jawed Habib Hair & Beauty',
    categoryType: 'Salon & Spa',
    templateId: 'salon_v1',
    ownerName: 'Sneha Kapadia',
    ownerEmail: 'owner.jawed@appnexa.com',
    ownerPhone: '+919876543216',
    city: 'Vadodara',
    address: 'Alkapuri Main Road, Opp. Center Square Mall, Vadodara 390007',
    googleReviewLink: 'https://maps.app.goo.gl/jawed123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frY0',
    status: 'grace_period',
    daysInGrace: 7, // Condition 7: 7 days in grace (renewal -7d, grace ends +23d)
    renewalDeltaDays: -7,
    graceDeltaDays: 23,
    totalScans: 390,
    reviewsBoosted: 330,
  },
  {
    num: 1008,
    code: 'APT-01008',
    brandName: 'Keventers Milkshakes & Desserts',
    categoryType: 'Cafe / Desserts',
    templateId: 'ice_cream_v1',
    ownerName: 'Anand Mehta',
    ownerEmail: 'owner.keventers@appnexa.com',
    ownerPhone: '+919876543217',
    city: 'Jaipur',
    address: 'MI Road, Near Raj Mandir Cinema, Jaipur, Rajasthan 302001',
    googleReviewLink: 'https://maps.app.goo.gl/keventers123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frYA',
    status: 'grace_period',
    daysInGrace: 15, // Condition 8: 15 days in grace (renewal -15d, grace ends +15d)
    renewalDeltaDays: -15,
    graceDeltaDays: 15,
    totalScans: 440,
    reviewsBoosted: 380,
  },
  {
    num: 1009,
    code: 'APT-01009',
    brandName: 'Urban Tadka Pure Veg',
    categoryType: 'Restaurant',
    templateId: 'restaurant_v1',
    ownerName: 'Rajesh Agrawal',
    ownerEmail: 'owner.tadka@appnexa.com',
    ownerPhone: '+919876543218',
    city: 'Delhi NCR',
    address: 'Sector 18 Market, Noida, Uttar Pradesh 201301',
    googleReviewLink: 'https://maps.app.goo.gl/tadka123',
    placeId: 'ChIJN1t_tDeuEmsRUsoyG83frYB',
    status: 'grace_period',
    daysInGrace: 30, // Condition 9: 30 days in grace (renewal -30d, grace ends today 0d)
    renewalDeltaDays: -30,
    graceDeltaDays: 0,
    totalScans: 590,
    reviewsBoosted: 510,
  },
];

async function clearCollections() {
  console.log('🧹 Clearing previous Firestore collections...');
  const collectionsToWipe = [
    'businesses',
    'employee_commissions',
    'commission_records',
    'notifications',
    'scan_logs',
    'subscription_override_logs',
  ];

  for (const col of collectionsToWipe) {
    const snap = await db.collection(col).get();
    if (!snap.empty) {
      console.log(`  Deleting ${snap.size} documents in ${col}...`);
      for (const doc of snap.docs) {
        if (col === 'businesses') {
          // delete branches subcollection
          const subBranches = await doc.ref.collection('branches').get();
          for (const b of subBranches.docs) await b.ref.delete();
          // delete scans subcollection
          const subScans = await doc.ref.collection('scans').get();
          for (const s of subScans.docs) await s.ref.delete();
          // delete feedback subcollection
          const subFeedback = await doc.ref.collection('feedback').get();
          for (const f of subFeedback.docs) await f.ref.delete();
        }
        await doc.ref.delete();
      }
    }
  }
}

async function clearStorage() {
  console.log('🧹 Clearing Storage files (logos/, qr_codes/)...');
  try {
    const prefixes = ['logos/', 'qr_codes/'];
    for (const prefix of prefixes) {
      await bucket.deleteFiles({ prefix, force: true });
    }
    console.log('  ✓ Storage cleared.');
  } catch (e) {
    console.log('  ⚠️ Storage cleanup warning:', e.message);
  }
}

async function createOwnerAuthUser(email, name) {
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, {
      displayName: name,
      password: OWNER_PASSWORD,
      emailVerified: true,
    });
    await auth.setCustomUserClaims(existing.uid, { role: 'owner' });
    return existing.uid;
  } catch (err) {
    if (err.code === 'auth/user-not-found' || err.code === 'auth/user-not-found') {
      const user = await auth.createUser({
        email,
        password: OWNER_PASSWORD,
        displayName: name,
        emailVerified: true,
      });
      await auth.setCustomUserClaims(user.uid, { role: 'owner' });
      return user.uid;
    }
    throw err;
  }
}

async function generateAndUploadQr(businessId, branchId) {
  try {
    const reviewUrl = `https://appnexa.co.in/r/${branchId}`;
    const pngBuffer = await QRCode.toBuffer(reviewUrl, {
      width: 512,
      margin: 2,
      color: { dark: '#00458B', light: '#FFFFFF' },
    });

    const filePath = `qr_codes/${businessId}_${branchId}.png`;
    const file = bucket.file(filePath);
    await file.save(pngBuffer, {
      contentType: 'image/png',
      metadata: { cacheControl: 'public, max-age=31536000' },
    });
    return filePath;
  } catch (e) {
    console.warn(`  ⚠️ QR generation skipped for ${branchId}:`, e.message);
    return `qr_codes/${businessId}_${branchId}.png`;
  }
}

async function seed() {
  const now = new Date();
  console.log(`\n============================================================`);
  console.log(`🚀 Seeding 9 Lifecycle Test Businesses into Firestore & Storage`);
  console.log(`============================================================\n`);

  await clearCollections();
  await clearStorage();

  const employeeId = 'admin';

  for (const def of BUSINESS_DEFS) {
    console.log(`\n🔹 [${def.code}] ${def.brandName} (${def.categoryType}) - ${def.status.toUpperCase()}`);

    // 1. Provision Firebase Auth Owner
    const ownerUid = await createOwnerAuthUser(def.ownerEmail, def.ownerName);
    console.log(`  👤 Owner Auth Provisioned: ${def.ownerEmail} (UID: ${ownerUid})`);

    // 2. Compute Dates
    const renewalDate = addDays(now, def.renewalDeltaDays);
    const graceEnds = def.graceDeltaDays !== null ? addDays(now, def.graceDeltaDays) : null;
    const createdAt = addDays(renewalDate, -365); // Created 1 year prior to renewal date

    // 3. Create Business Doc
    const bizRef = db.collection('businesses').doc();
    const branchRef = bizRef.collection('branches').doc();

    const qrStoragePath = await generateAndUploadQr(bizRef.id, branchRef.id);

    const bizData = {
      business_code: def.code,
      business_number: def.num,
      is_test_account: false,
      brand_name: def.brandName,
      category_type: def.categoryType,
      default_category_template_id: def.templateId,
      logo_url: `https://ui-avatars.com/api/?name=${encodeURIComponent(def.brandName)}&background=00458B&color=fff&size=256`,
      enrolled_by: employeeId,
      enrolled_by_original: employeeId,
      currently_managed_by: employeeId,
      owner_auth_uid: ownerUid,
      owner_name: def.ownerName,
      owner_email: def.ownerEmail,
      owner_phone: def.ownerPhone,
      subscription_status: def.status,
      payment_mode: 'cash',
      renewal_date: Timestamp.fromDate(renewalDate),
      grace_period_ends: graceEnds ? Timestamp.fromDate(graceEnds) : null,
      created_at: Timestamp.fromDate(createdAt),
      active_categories: {
        'Quality & Taste': true,
        'Staff Behavior & Service': true,
        'Ambiance & Cleanliness': true,
        'Value for Money': true,
      },
    };

    await bizRef.set(bizData);

    // 4. Create Branch Doc
    const branchData = {
      branch_name: 'Main Branch',
      address: def.address,
      whatsapp_number: def.ownerPhone,
      google_review_link: def.googleReviewLink,
      place_id: def.placeId,
      subscription_status: def.status,
      payment_mode: 'cash',
      enrolled_by: employeeId,
      plain_qr_storage_path: qrStoragePath,
      standee_status: 'delivered',
      standee_status_updated_at: Timestamp.fromDate(createdAt),
      star_routing_config: {
        '1': 'whatsapp',
        '2': 'whatsapp',
        '3': 'whatsapp',
        '4': 'google',
        '5': 'google',
      },
      stats_summary: {
        total_scans: def.totalScans,
        total_reviews_redirected: def.reviewsBoosted,
        monthly_google_reviews: Math.round(def.reviewsBoosted / 4),
        star_counts: {
          '5': Math.round(def.reviewsBoosted * 0.85),
          '4': Math.round(def.reviewsBoosted * 0.15),
          '3': Math.round((def.totalScans - def.reviewsBoosted) * 0.5),
          '2': Math.round((def.totalScans - def.reviewsBoosted) * 0.3),
          '1': Math.round((def.totalScans - def.reviewsBoosted) * 0.2),
        },
      },
    };

    await branchRef.set(branchData);

    // 5. Seed historical scan logs for rich dashboard visual graphs
    const scanCount = 30;
    const batch = db.batch();
    for (let i = 0; i < scanCount; i++) {
      const scanDoc = bizRef.collection('scans').doc();
      const scanDate = addDays(now, -Math.floor(Math.random() * 45));
      const star = Math.random() > 0.18 ? 5 : (Math.random() > 0.4 ? 4 : Math.floor(Math.random() * 3) + 1);
      batch.set(scanDoc, {
        branch_id: branchRef.id,
        star_rating: star,
        action_taken: star >= 4 ? 'google_maps' : 'whatsapp',
        timestamp: Timestamp.fromDate(scanDate),
        session_token: `sess_${Math.random().toString(36).substring(2, 9)}`,
      });
    }
    await batch.commit();

    console.log(`  ✓ Business Created: ID: ${bizRef.id} | Code: ${def.code}`);
    console.log(`  ✓ Renewal: ${renewalDate.toDateString()} (${def.status.toUpperCase()})`);
  }

  // 6. Reset sequential business counter to 1009
  await db.collection('counters').doc('business_counter').set({
    last_number: 1009,
    updated_at: FieldValue.serverTimestamp(),
  });
  console.log(`\n🔢 Atomic Counter reset: 'counters/business_counter' -> 1009 (Next will be APT-01010)`);

  console.log(`\n============================================================`);
  console.log(`🎉 ALL 9 TEST BUSINESSES SEEDED SUCCESSFULLY!`);
  console.log(`============================================================\n`);
}

seed().then(() => {
  process.exit(0);
}).catch((e) => {
  console.error('❌ Seeding failed:', e);
  process.exit(1);
});
