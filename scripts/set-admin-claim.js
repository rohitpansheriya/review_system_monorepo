#!/usr/bin/env node
// scripts/set-admin-claim.js
//
// Sets the custom claim { role: 'admin' } on a user in PRODUCTION Firebase Auth.
// Also creates the employees/{uid} doc with role: 'admin'.
//
// Usage (against LIVE Firebase — NOT emulator):
//   node scripts/set-admin-claim.js admin@youremail.com
//
// Make sure you are logged in:  firebase login
// And using the right project:  firebase use review-system-prod-49b7a

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

// DO NOT set emulator env vars — this runs against production
delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
delete process.env.FIRESTORE_EMULATOR_HOST;

const email = process.argv[2];
if (!email) {
  console.error('Usage: node scripts/set-admin-claim.js <admin-email>');
  process.exit(1);
}

initializeApp({
  projectId: 'review-system-prod-49b7a',
  credential: applicationDefault(),
});

const auth = getAuth();
const db = getFirestore();

async function run() {
  console.log(`\n🔑 Setting admin claim for: ${email}\n`);

  // 1. Find the user
  let user;
  try {
    user = await auth.getUserByEmail(email);
    console.log(`  ✅ Found user: uid=${user.uid}, displayName=${user.displayName}`);
  } catch (e) {
    console.error(`  ❌ User not found: ${email}`);
    console.error('     Create the user in Firebase Console first, then re-run this script.');
    process.exit(1);
  }

  // 2. Set custom claims
  await auth.setCustomUserClaims(user.uid, { role: 'admin' });
  console.log(`  ✅ Custom claim set: { role: 'admin' }`);

  // 3. Create employees/{uid} doc (the app reads this for profile info)
  await db.collection('employees').doc(user.uid).set({
    name: user.displayName || 'Platform Admin',
    contact: email,
    role: 'admin',
    active: true,
    total_enrollments: 0,
    this_month_enrollments: 0,
  }, { merge: true });
  console.log(`  ✅ employees/${user.uid} doc created`);

  // 4. Verify
  const updated = await auth.getUser(user.uid);
  console.log(`  ✅ Verified claims:`, updated.customClaims);

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('✅  Done! The user must LOG OUT and LOG BACK IN for claims to take effect.');
  console.log('    (Custom claims are baked into the ID token — a fresh token is needed.)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

run().catch(err => {
  console.error('❌ Failed:', err.message);
  process.exit(1);
});
