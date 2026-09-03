// scripts/test-security-rules.js
// Tests for hardened employee security rules using the Firestore REST emulator API.
// Uses firebase-admin (no security rules) for setup/cleanup,
// and the emulator's /__rules_test_sdk/ endpoint pattern for rule-enforcement tests.
//
// APPROACH: The Firestore emulator exposes per-user impersonation via the
// x-forwarded-authorization header with a fake JWT (emulator-only feature).
// We craft a minimal JWT payload and call the REST API with it.

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const https = require('http');

const adminApp = initializeApp({ projectId: 'review-system-prod-49b7a' });
const adminDb  = getFirestore(adminApp);

const PROJECT = 'review-system-prod-49b7a';
const BASE    = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;

let passed = 0; let failed = 0;

// Build a fake emulator JWT for the given employee UID + custom claim role=employee
function makeToken(uid, role = 'employee') {
  const header  = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    sub: uid,
    uid,
    user_id: uid,
    role,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600,
  })).toString('base64url');
  return `${header}.${payload}.`;
}

// Make a REST request with emulator auth (simulates client SDK with a real user)
function restRequest(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${BASE}/${path}`);
    const options = {
      hostname: '127.0.0.1',
      port: 8080,
      path: url.pathname + url.search,
      method,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        const parsed = data ? JSON.parse(data) : {};
        resolve({ status: res.statusCode, body: parsed });
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function expect(label, fn, shouldSucceed) {
  try {
    const result = await fn();
    const ok = result.status >= 200 && result.status < 300;
    if (shouldSucceed && ok) {
      console.log(`  ✅  ${label}`);
      passed++;
    } else if (!shouldSucceed && !ok) {
      console.log(`  ✅  ${label} — correctly DENIED (${result.status})`);
      passed++;
    } else if (shouldSucceed && !ok) {
      console.error(`  ❌  ${label} — should SUCCEED but got ${result.status}: ${JSON.stringify(result.body)}`);
      failed++;
    } else {
      console.error(`  ❌  ${label} — should be DENIED but got ${result.status}`);
      failed++;
    }
  } catch (e) {
    console.error(`  ❌  ${label} — error: ${e.message}`);
    failed++;
  }
}

// ── Firestore REST PATCH helper — only sends the fields in `fields` map ───────
function buildPatchBody(fields) {
  const firestoreFields = {};
  for (const [k, v] of Object.entries(fields)) {
    if (typeof v === 'string') firestoreFields[k] = { stringValue: v };
    else if (v instanceof Date) firestoreFields[k] = { timestampValue: v.toISOString() };
    else if (v === null)        firestoreFields[k] = { nullValue: null };
    else if (typeof v === 'number') firestoreFields[k] = { integerValue: v };
  }
  return { fields: firestoreFields };
}

function buildMask(fields) {
  return Object.keys(fields).join(',');
}

async function main() {
  // Find employee UID from seed
  const empSnap = await adminDb.collection('employees').get();
  let empUid;
  for (const doc of empSnap.docs) {
    const d = doc.data();
    if (d.role === 'employee' && d.name && d.name.includes('A')) {
      empUid = doc.id; break;
    }
  }
  if (!empUid && empSnap.docs.length > 0) empUid = empSnap.docs[0].id;
  if (!empUid) { console.error('No employee found — run seed-employee-user.js first'); process.exit(1); }

  console.log(`\nEmployee UID for tests: ${empUid}`);
  const token = makeToken(empUid);

  // ── Setup via admin SDK ─────────────────────────────────────────────────────
  const PENDING_ID = 'sec-test-pending';
  const ACTIVE_ID  = 'sec-test-active';

  await adminDb.doc(`businesses/${PENDING_ID}`).set({
    brand_name: 'Sec Test Pending', logo_url: '', category_type: 'Restaurant',
    enrolled_by: empUid, enrolled_by_original: empUid, currently_managed_by: empUid,
    subscription_status: 'pending_payment', created_at: Timestamp.now(),
    owner_email: 'test@test.com', owner_name: 'Test', owner_phone: '+91999',
  });

  await adminDb.doc(`businesses/${ACTIVE_ID}`).set({
    brand_name: 'Sec Test Active', logo_url: '', category_type: 'Cafe',
    enrolled_by: empUid, enrolled_by_original: empUid, currently_managed_by: empUid,
    subscription_status: 'active',
    renewal_date: Timestamp.fromDate(new Date(Date.now() + 365*86400*1000)),
    created_at: Timestamp.now(),
    owner_email: 'test2@test.com', owner_name: 'Test2', owner_phone: '+91998',
  });

  await adminDb.doc(`businesses/${ACTIVE_ID}/branches/test-branch`).set({
    branch_name: 'Main', address: '123 Test', whatsapp_number: '+91999',
    star_routing_config: {}, place_id: null,
  });

  console.log('\n── Security Rule Tests ──────────────────────────────────────────');

  // T1 — cannot flip subscription_status to "active"
  await expect(
    'T1: employee cannot flip subscription_status=active',
    () => restRequest('PATCH',
      `businesses/${PENDING_ID}?updateMask.fieldPaths=subscription_status`,
      buildPatchBody({ subscription_status: 'active' }), token),
    false
  );

  // T2 — cannot change renewal_date
  await expect(
    'T2: employee cannot change renewal_date',
    () => restRequest('PATCH',
      `businesses/${PENDING_ID}?updateMask.fieldPaths=renewal_date`,
      buildPatchBody({ renewal_date: new Date() }), token),
    false
  );

  // T3 — cannot change enrolled_by
  await expect(
    'T3: employee cannot change enrolled_by',
    () => restRequest('PATCH',
      `businesses/${PENDING_ID}?updateMask.fieldPaths=enrolled_by`,
      buildPatchBody({ enrolled_by: 'attacker-uid' }), token),
    false
  );

  // T4 — CAN delete pending_payment business
  await expect(
    'T4: employee CAN delete pending_payment business',
    () => restRequest('DELETE', `businesses/${PENDING_ID}`, null, token),
    true
  );

  // T5 — CANNOT delete active business
  await expect(
    'T5: employee CANNOT delete active business',
    () => restRequest('DELETE', `businesses/${ACTIVE_ID}`, null, token),
    false
  );

  // T6 — CAN update brand_name on active business
  await expect(
    'T6: employee CAN update brand_name on active business',
    () => restRequest('PATCH',
      `businesses/${ACTIVE_ID}?updateMask.fieldPaths=brand_name`,
      buildPatchBody({ brand_name: 'Updated Brand' }), token),
    true
  );

  // T7 — CANNOT delete branch of active business
  await expect(
    'T7: employee CANNOT delete branch of active business',
    () => restRequest('DELETE',
      `businesses/${ACTIVE_ID}/branches/test-branch`, null, token),
    false
  );

  // T8 — CANNOT update business enrolled by someone else
  const OTHER_EMP_BIZ = 'sec-test-other-emp';
  await adminDb.doc(`businesses/${OTHER_EMP_BIZ}`).set({
    brand_name: 'Other Emp Biz',
    enrolled_by: 'someone_else_999',
    subscription_status: 'active',
    created_at: Timestamp.now(),
  });

  await expect(
    'T8: employee CANNOT update business enrolled by another employee (enrolled_by isolation)',
    () => restRequest('PATCH',
      `businesses/${OTHER_EMP_BIZ}?updateMask.fieldPaths=brand_name`,
      buildPatchBody({ brand_name: 'Hacked Brand' }), token),
    false
  );

  // T9 — Deactivated employee is DENIED access to their own enrolled business
  await adminDb.doc(`employees/${empUid}`).update({
    status: 'inactive',
    active: false,
  });

  await expect(
    'T9: deactivated employee is DENIED update to their own enrolled business',
    () => restRequest('PATCH',
      `businesses/${ACTIVE_ID}?updateMask.fieldPaths=brand_name`,
      buildPatchBody({ brand_name: 'Deactivated Emp Edit' }), token),
    false
  );

  // Restore employee active state for other test suites
  await adminDb.doc(`employees/${empUid}`).update({
    status: 'active',
    active: true,
  });

  // ── Cleanup ───────────────────────────────────────────────────────────────
  await adminDb.doc(`businesses/${PENDING_ID}`).delete().catch(() => {});
  await adminDb.doc(`businesses/${ACTIVE_ID}/branches/test-branch`).delete().catch(() => {});
  await adminDb.doc(`businesses/${ACTIVE_ID}`).delete().catch(() => {});
  await adminDb.doc(`businesses/${OTHER_EMP_BIZ}`).delete().catch(() => {});

  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`Results: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch(e => { console.error(e); process.exit(1); });
