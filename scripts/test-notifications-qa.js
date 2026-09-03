/**
 * scripts/test-notifications-qa.js
 *
 * Automated QA harness for the Notifications System (doc 08).
 * Covers T1–T14 automatically. T10 and T16/T17 require manual steps
 * described in the QA plan artifact.
 *
 * USAGE:
 *   Full run (clears QA notifications first, then asserts):
 *     npm run test:qa
 *
 *   Idempotency mode (does NOT clear — counts must stay the same):
 *     npm run test:qa -- --idempotency
 *
 *   Single test:
 *     npm run test:qa -- --test T6
 *
 * ENVIRONMENT:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 must be set.
 *   The scheduled functions must be reachable on port 5001.
 *
 * BEFORE RUNNING:
 *   npm run seed && npm run test:statuses    (seeds all businesses)
 */

'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID   = 'review-system-prod-49b7a';
const FUNC_HOST    = 'http://127.0.0.1:5001';
const FUNC_REGION  = 'asia-south1';
const FUNC_BASE    = `${FUNC_HOST}/${PROJECT_ID}/${FUNC_REGION}`;
const WAIT_MS      = 7000;  // ms to wait after triggering function

if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();

// ─────────────────────────────────────────────────────────────────────────────
// Test case definitions
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @typedef {{
 *   id: string,
 *   description: string,
 *   bizId: string,
 *   expectedCount: number,
 *   expectedType: string|null,
 *   expectedRoles: string[]|null,
 *   extraChecks?: (docs: object[]) => {ok: boolean, note: string}[]
 * }} TestCase
 */

/** @type {TestCase[]} */
const TESTS = [
  // ── Boundary / off-by-one ────────────────────────────────────────────────
  {
    id: 'T1',
    description: 'Boundary +29d — NOT in WINDOWS [30,15,7,1], must fire nothing',
    bizId: 'tst-qa-bound-29',
    expectedCount: 0,
    expectedType: null,
    expectedRoles: null,
  },
  {
    id: 'T2',
    description: 'Boundary +31d — NOT in WINDOWS, must fire nothing',
    bizId: 'tst-qa-bound-31',
    expectedCount: 0,
    expectedType: null,
    expectedRoles: null,
  },
  {
    id: 'T3',
    description: 'Boundary day 0 — renewal today, daysDiff=0 not in WINDOWS',
    bizId: 'tst-qa-bound-0',
    expectedCount: 0,
    expectedType: null,
    expectedRoles: null,
  },
  {
    id: 'T4',
    description: 'Boundary -1d — past renewal, daysDiff=-1 not in WINDOWS',
    bizId: 'tst-qa-bound-neg',
    expectedCount: 0,
    expectedType: null,
    expectedRoles: null,
  },

  // ── Status gating ────────────────────────────────────────────────────────
  {
    id: 'T6',
    description: 'grace_period status — daysDiff<0, no reminder fires',
    bizId: 'tst-qa-grace',
    expectedCount: 0,
    expectedType: null,
    expectedRoles: null,
  },

  // ── Channel isolation ────────────────────────────────────────────────────
  {
    id: 'T8',
    description: 'FCM null token — Firestore+email succeed, push skipped (debug log only)',
    bizId: 'tst-qa-fcm-null',
    expectedCount: 2,
    expectedType: 'renewal_reminder_7',
    expectedRoles: ['employee', 'owner'],
  },
  {
    id: 'T9',
    description: 'FCM garbage token — Firestore+email still succeed, FCM WARN logged',
    bizId: 'tst-qa-fcm-bad',
    expectedCount: 2,
    expectedType: 'renewal_reminder_7',
    expectedRoles: ['employee', 'owner'],
  },

  // ── Recipient routing ────────────────────────────────────────────────────
  {
    id: 'T11',
    description: 'Real employee — owner + employee both notified',
    bizId: 'tst-qa-emp-real',
    expectedCount: 2,
    expectedType: 'renewal_reminder_7',
    expectedRoles: ['employee', 'owner'],
  },
  {
    id: 'T12',
    description: 'enrolled_by=admin — owner only, employee cleanly skipped',
    bizId: 'tst-qa-emp-admin',
    expectedCount: 1,
    expectedType: 'renewal_reminder_7',
    expectedRoles: ['owner'],
  },
  {
    id: 'T13',
    description: 'Reassigned to emp-002 — emp-002 notified, NOT emp-001',
    bizId: 'tst-qa-reassigned',
    expectedCount: 2,
    expectedType: 'renewal_reminder_7',
    expectedRoles: ['employee', 'owner'],
    extraChecks: (docs) => {
      const empDoc = docs.find(d => d.recipient_role === 'employee');
      if (!empDoc) {
        return [{ ok: false, note: 'No employee doc found at all' }];
      }
      const isEmp2 = empDoc.recipient_name === 'Test Employee 2';
      const isEmp1 = empDoc.recipient_name === 'Test Employee 1';
      return [
        { ok: isEmp2, note: isEmp2
            ? 'Employee doc has recipient_name=Test Employee 2 ✓'
            : `Employee doc has recipient_name="${empDoc.recipient_name}" — expected "Test Employee 2"` },
        { ok: !isEmp1, note: !isEmp1
            ? 'Test Employee 1 correctly NOT notified ✓'
            : 'FAIL: Test Employee 1 was notified (enrolled_by used instead of currently_managed_by)' },
      ];
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

async function triggerFunction(fnName) {
  const url = `${FUNC_BASE}/${fnName}`;
  process.stdout.write(`  Triggering ${fnName}… `);
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
  });
  console.log(`HTTP ${res.status}`);
  if (!res.ok) {
    const text = await res.text().catch(() => '(unreadable)');
    throw new Error(`Function returned ${res.status}: ${text.slice(0, 200)}`);
  }
  return res.status;
}

async function wait(ms) {
  process.stdout.write(`  Waiting ${ms / 1000}s for async processing… `);
  await new Promise(r => setTimeout(r, ms));
  console.log('done.');
}

async function getNotifsForBiz(bizId) {
  const snap = await db.collection('notifications')
    .where('business_id', '==', bizId)
    .get();
  return snap.docs.map(d => d.data());
}

async function deleteNotifsForBiz(bizId) {
  const snap = await db.collection('notifications')
    .where('business_id', '==', bizId)
    .get();
  await Promise.all(snap.docs.map(d => d.ref.delete()));
  return snap.size;
}

// ─────────────────────────────────────────────────────────────────────────────
// T14 — Admin digest check (one summary, not N per-business)
// ─────────────────────────────────────────────────────────────────────────────

async function runT14(triggerDigest) {
  console.log('\n──────────────────────────────────────────────────────────────');
  console.log('T14 — Admin digest: 1 digest record, not N per-business');
  console.log('──────────────────────────────────────────────────────────────');

  // Delete existing digest notifications for a clean baseline
  const digSnap = await db.collection('notifications')
    .where('type', '==', 'admin_weekly_digest').get();
  await Promise.all(digSnap.docs.map(d => d.ref.delete()));
  console.log(`  Cleared ${digSnap.size} existing admin_weekly_digest notifications.`);

  if (triggerDigest) {
    await triggerFunction('sendAdminDigest-0');
    await wait(4000);
  } else {
    console.log('  (Digest already triggered externally — checking results only)');
  }

  const afterSnap = await db.collection('notifications')
    .where('type', '==', 'admin_weekly_digest').get();
  const count = afterSnap.size;

  // Count businesses in 0-30d window for informational purposes
  const allBiz = await db.collection('businesses')
    .where('subscription_status', 'in', ['active', 'grace_period'])
    .get();
  const now = Date.now();
  const DAY = 86400000;
  const inWindow = allBiz.docs.filter(doc => {
    const rd = doc.data().renewal_date;
    if (!rd || typeof rd.toDate !== 'function') return false;
    const d = Math.round((rd.toDate().getTime() - now) / DAY);
    return d >= 0 && d <= 30;
  }).length;

  const pass = count === 1;
  const status = pass ? '✅ PASS' : '❌ FAIL';
  console.log(`  ${status} — expected 1 digest notification, got ${count}`);
  console.log(`  (Businesses in 0-30d window: ${inWindow} — all listed in 1 email)`);
  if (!pass) {
    if (count === 0) console.log('  → Digest function may not have run or returned early');
    if (count > 1) console.log('  → Digest is writing one record per business (BUG)');
  }
  return pass;
}

// ─────────────────────────────────────────────────────────────────────────────
// T5 — Idempotency: compare counts before and after a second run
// ─────────────────────────────────────────────────────────────────────────────

async function runIdempotencyCheck(tests) {
  console.log('\n══════════════════════════════════════════════════════════════');
  console.log('T5 — IDEMPOTENCY: Second run must not increase notification counts');
  console.log('══════════════════════════════════════════════════════════════\n');

  // Snapshot counts before second trigger
  const before = {};
  for (const t of tests.filter(t => t.expectedCount > 0)) {
    const docs = await getNotifsForBiz(t.bizId);
    before[t.bizId] = docs.length;
  }
  console.log('  Counts before second trigger:');
  for (const [bizId, c] of Object.entries(before)) {
    console.log(`    ${bizId.padEnd(22)}: ${c}`);
  }

  await triggerFunction('sendRenewalReminders-0');
  await wait(WAIT_MS);

  console.log('\n  Counts after second trigger:');
  let allPass = true;
  for (const t of tests.filter(t => t.expectedCount > 0)) {
    const after = (await getNotifsForBiz(t.bizId)).length;
    const changed = after !== before[t.bizId];
    const pass = !changed;
    if (!pass) allPass = false;
    const symbol = pass ? '✅' : '❌';
    const change = changed ? ` → INCREASED to ${after} (was ${before[t.bizId]})` : ` → unchanged ✓`;
    console.log(`    ${symbol} ${t.bizId.padEnd(22)}: ${after}${change}`);
  }

  console.log();
  return allPass;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main runner
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const idempotencyMode = args.includes('--idempotency');
  const singleTest = args.find(a => a === '--test') ? args[args.indexOf('--test') + 1] : null;

  const testsToRun = singleTest
    ? TESTS.filter(t => t.id === singleTest)
    : TESTS;

  if (testsToRun.length === 0) {
    console.error(`❌ Unknown test: ${singleTest}. Valid IDs: ${TESTS.map(t => t.id).join(', ')}`);
    process.exit(1);
  }

  console.log('\n🔬 Notifications System QA Harness');
  console.log('  Environment: Firebase Emulator Suite');
  if (idempotencyMode) console.log('  Mode: IDEMPOTENCY (no notification clear — counts must stay same)');
  else if (singleTest) console.log(`  Mode: Single test (${singleTest})`);
  console.log();

  // ── Step 1: clear QA notifications (unless idempotency mode) ──────────────
  if (!idempotencyMode) {
    process.stdout.write('  Clearing existing QA notification records… ');
    let cleared = 0;
    for (const t of testsToRun) {
      cleared += await deleteNotifsForBiz(t.bizId);
    }
    console.log(`cleared ${cleared} docs.`);
  }

  // ── Step 2: trigger sendRenewalReminders ──────────────────────────────────
  if (idempotencyMode) {
    return runIdempotencyCheck(testsToRun);
  }

  console.log();
  await triggerFunction('sendRenewalReminders-0');
  await wait(WAIT_MS);

  // ── Step 3: assert results per test ───────────────────────────────────────
  console.log('\n──────────────────────────────────────────────────────────────');
  console.log('Results');
  console.log('──────────────────────────────────────────────────────────────');

  const results = [];

  for (const t of testsToRun) {
    const docs = await getNotifsForBiz(t.bizId);
    const count = docs.length;
    const roles = docs.map(d => d.recipient_role).sort();
    const types = [...new Set(docs.map(d => d.type))];

    let pass = true;
    const notes = [];

    // Check count
    if (count !== t.expectedCount) {
      pass = false;
      notes.push(`Count: expected ${t.expectedCount}, got ${count}`);
    } else {
      notes.push(`Count: ${count} ✓`);
    }

    // Check type (only for non-zero cases)
    if (t.expectedType && count > 0) {
      if (!types.includes(t.expectedType)) {
        pass = false;
        notes.push(`Type: expected ${t.expectedType}, got [${types.join(',')}]`);
      } else {
        notes.push(`Type: ${t.expectedType} ✓`);
      }
    }

    // Check roles (only for non-zero cases)
    if (t.expectedRoles && count > 0) {
      const rolesMatch = t.expectedRoles.every(r => roles.includes(r))
        && roles.length === t.expectedRoles.length;
      if (!rolesMatch) {
        pass = false;
        notes.push(`Roles: expected [${t.expectedRoles.join(',')}], got [${roles.join(',')}]`);
      } else {
        notes.push(`Roles: [${roles.join(',')}] ✓`);
      }
    }

    // Extra checks (e.g. T13 recipient_name assertion)
    if (t.extraChecks) {
      const extras = t.extraChecks(docs);
      for (const ex of extras) {
        if (!ex.ok) pass = false;
        notes.push(ex.note);
      }
    }

    const symbol = pass ? '✅ PASS' : '❌ FAIL';
    console.log(`\n${symbol}  ${t.id} — ${t.description}`);
    for (const n of notes) console.log(`           ${n}`);
    results.push({ id: t.id, pass, description: t.description });
  }

  // ── Step 4: run T14 if not single-test mode (or T14 was requested) ────────
  let t14Pass = null;
  if (!singleTest || singleTest === 'T14') {
    t14Pass = await runT14(/* triggerDigest= */ true);
    results.push({ id: 'T14', pass: t14Pass, description: 'Admin digest: 1 record not N' });
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log('\n══════════════════════════════════════════════════════════════');
  const passing = results.filter(r => r.pass).length;
  console.log(`Summary: ${passing}/${results.length} tests passed`);
  console.log('──────────────────────────────────────────────────────────────');
  for (const r of results) {
    console.log(`  ${r.pass ? '✅' : '❌'} ${r.id.padEnd(4)} ${r.description}`);
  }

  if (!singleTest && !idempotencyMode) {
    console.log('\n─────────────────────────────────────────────────────────────');
    console.log('Manual steps still required:');
    console.log('  T5  — run `npm run test:qa -- --idempotency` immediately after this');
    console.log('  T7  — delete tst-biz-g doc, re-trigger, verify 0 notifications');
    console.log('  T10 — set bad BREVO_API_KEY, restart emulators, re-seed, check Firestore');
    console.log('  T16 — check support@appnexa.co.in inbox + spam');
    console.log('  T17 — DEFERRED until Flutter panel (doc 02/03) is built');
  }

  console.log();
  process.exit(results.every(r => r.pass) ? 0 : 1);
}

main().catch(err => {
  console.error('\n❌ Fatal error in QA harness:', err.message);
  process.exit(1);
});
