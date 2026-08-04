/**
 * scripts/test-doc-05.js
 *
 * LOCAL-ONLY integration test for docs/05-payment-subscription-renewal.md.
 * DO NOT deploy. DO NOT commit credentials. For local emulator testing only.
 *
 * ─── What this script does ────────────────────────────────────────────────────
 *
 *   SECTION A  createOrder logic
 *     Calls the Razorpay Test API directly (same code path as the Cloud Function)
 *     to create a real ₹1999 order. Prints the full Razorpay response.
 *
 *   SECTION B  createSubscription logic
 *     Creates a real Razorpay subscription against the RAZORPAY_PLAN_ID.
 *     Prints the full response. Skipped gracefully if plan ID is not set.
 *
 *   SECTION C  razorpayWebhook — end-to-end
 *     1. Seeds a test business doc in the Firestore emulator.
 *     2. Builds a realistic `payment.captured` webhook payload using the
 *        order ID returned in Section A.
 *     3. Signs the payload with HMAC-SHA256 using RAZORPAY_WEBHOOK_SECRET.
 *     4. POSTs to the locally running razorpayWebhook Cloud Function.
 *     5. Reads back the business doc from the emulator and prints
 *        subscription_status and renewal_date — PASS/FAIL.
 *     6. Confirms a commission_records document was created.
 *
 * ─── Prerequisites ────────────────────────────────────────────────────────────
 *
 *   1. Emulators running:
 *        firebase emulators:start --only firestore,functions,hosting
 *
 *   2. Secrets in functions/.secret.local  (KEY=VALUE, one per line):
 *        RAZORPAY_KEY_ID=rzp_test_...
 *        RAZORPAY_KEY_SECRET=...
 *        RAZORPAY_WEBHOOK_SECRET=my_local_test_secret_123
 *
 *      OR as environment variables before running this script.
 *
 *   3. Plan ID (optional — for subscription test) in functions/.env.local:
 *        RAZORPAY_PLAN_ID=plan_...
 *
 * ─── Usage ───────────────────────────────────────────────────────────────────
 *
 *   From the repo root:
 *     node scripts/test-doc-05.js
 *
 *   Override ports if needed:
 *     FUNCTIONS_PORT=5001 FIRESTORE_PORT=8080 node scripts/test-doc-05.js
 */

'use strict';

const fs     = require('fs');
const path   = require('path');
const http   = require('http');
const crypto = require('crypto');

// ─── Config ──────────────────────────────────────────────────────────────────

const PROJECT_ID       = 'review-system-prod-49b7a';
const REGION           = 'asia-south1';
const FUNCTIONS_PORT   = parseInt(process.env['FUNCTIONS_PORT']   || '5001', 10);
const FIRESTORE_PORT   = parseInt(process.env['FIRESTORE_PORT']   || '8080', 10);
const FUNCTIONS_HOST   = process.env['FUNCTIONS_HOST']   || '127.0.0.1';
const FIRESTORE_HOST   = process.env['FIRESTORE_HOST']   || '127.0.0.1';

const WEBHOOK_URL_PATH =
  `/${PROJECT_ID}/${REGION}/razorpayWebhook`;

/** Business ID used throughout this test run. */
const TEST_BIZ_ID = `test-biz-doc05-${Date.now()}`;

// ─── Load secrets from functions/.secret.local then env vars ─────────────────

/**
 * Parses a KEY=VALUE file (dotenv-style, ignoring comments and blanks).
 * Returns a plain object.
 */
function parseDotenv(filePath) {
  const result = {};
  if (!fs.existsSync(filePath)) return result;
  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eqIdx = line.indexOf('=');
    if (eqIdx < 0) continue;
    const key = line.slice(0, eqIdx).trim();
    const val = line.slice(eqIdx + 1).trim()
      // strip surrounding quotes if present
      .replace(/^["']|["']$/g, '');
    if (key) result[key] = val;
  }
  return result;
}

const secretsFile  = path.join(__dirname, '../functions/.secret.local');
const envLocalFile = path.join(__dirname, '../functions/.env.local');
const envProdFile  = path.join(__dirname, `../functions/.env.${PROJECT_ID}`);

const secretsFromFile = parseDotenv(secretsFile);
const paramsLocal     = parseDotenv(envLocalFile);
const paramsProd      = parseDotenv(envProdFile);

/**
 * Look up a value from: environment variable → .secret.local → fallback.
 */
function getEnv(key, fallback) {
  return (
    process.env[key] ||
    secretsFromFile[key] ||
    paramsLocal[key] ||
    paramsProd[key] ||
    fallback
  );
}

const RAZORPAY_KEY_ID       = getEnv('RAZORPAY_KEY_ID', '');
const RAZORPAY_KEY_SECRET   = getEnv('RAZORPAY_KEY_SECRET', '');
const RAZORPAY_WEBHOOK_SECRET = getEnv('RAZORPAY_WEBHOOK_SECRET', '');
const RAZORPAY_PLAN_ID      = getEnv('RAZORPAY_PLAN_ID', '');

// ─── Validate required credentials ───────────────────────────────────────────

const missing = [];
if (!RAZORPAY_KEY_ID)         missing.push('RAZORPAY_KEY_ID');
if (!RAZORPAY_KEY_SECRET)     missing.push('RAZORPAY_KEY_SECRET');
if (!RAZORPAY_WEBHOOK_SECRET) missing.push('RAZORPAY_WEBHOOK_SECRET');

if (missing.length > 0) {
  console.error('\n❌  Missing required credentials:', missing.join(', '));
  console.error('\n   Add them to functions/.secret.local (KEY=VALUE, one per line)');
  console.error('   or export them as environment variables before running this script.\n');
  process.exit(1);
}

if (!RAZORPAY_KEY_ID.startsWith('rzp_test_')) {
  console.warn('\n⚠️   RAZORPAY_KEY_ID does not start with "rzp_test_".');
  console.warn('   This script is intended for TEST MODE only. Abort if using live keys.\n');
}

// ─── Razorpay SDK (loaded from functions/node_modules) ───────────────────────

const functionsModules = path.join(__dirname, '../functions/node_modules');
let Razorpay;
try {
  Razorpay = require(path.join(functionsModules, 'razorpay'));
} catch {
  console.error(
    '\n❌  Could not load razorpay from functions/node_modules.\n' +
    '   Run: cd functions && npm install\n'
  );
  process.exit(1);
}

const razorpay = new Razorpay({
  key_id:     RAZORPAY_KEY_ID,
  key_secret: RAZORPAY_KEY_SECRET,
});

// ─── Firebase Admin SDK (root node_modules — emulator only) ──────────────────

// Must be set BEFORE require('firebase-admin/...')
process.env['FIRESTORE_EMULATOR_HOST'] = `${FIRESTORE_HOST}:${FIRESTORE_PORT}`;

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');

if (getApps().length === 0) {
  initializeApp({ projectId: PROJECT_ID });
}
const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** ANSI colour helpers for readable output. */
const c = {
  bold:  (s) => `\x1b[1m${s}\x1b[0m`,
  green: (s) => `\x1b[32m${s}\x1b[0m`,
  red:   (s) => `\x1b[31m${s}\x1b[0m`,
  cyan:  (s) => `\x1b[36m${s}\x1b[0m`,
  grey:  (s) => `\x1b[90m${s}\x1b[0m`,
  yellow:(s) => `\x1b[33m${s}\x1b[0m`,
};

function section(title) {
  console.log('\n' + c.bold(c.cyan('─'.repeat(60))));
  console.log(c.bold(c.cyan(`  ${title}`)));
  console.log(c.bold(c.cyan('─'.repeat(60))));
}

function pass(msg) { console.log(c.green(`  ✅  ${msg}`)); }
function fail(msg) { console.log(c.red(`  ❌  ${msg}`)); }
function info(msg) { console.log(c.grey(`  ℹ   ${msg}`)); }
function warn(msg) { console.log(c.yellow(`  ⚠️   ${msg}`)); }

/**
 * Signs a string body with HMAC-SHA256 using the webhook secret.
 */
function signWebhookPayload(body) {
  return crypto
    .createHmac('sha256', RAZORPAY_WEBHOOK_SECRET)
    .update(body, 'utf8')
    .digest('hex');
}

/**
 * Sends an HTTP POST to the local Functions emulator.
 * Returns a promise resolving to { status, body }.
 */
function httpPost(host, port, urlPath, body, headers) {
  return new Promise((resolve, reject) => {
    const bodyBuf = Buffer.from(body, 'utf8');
    const options = {
      hostname: host,
      port,
      path: urlPath,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': bodyBuf.length,
        ...headers,
      },
    };
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.write(bodyBuf);
    req.end();
  });
}

/** Sleep for ms milliseconds. */
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// ─── MAIN ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('\n' + c.bold('🧪  test-doc-05.js — Payment, Subscription & Renewal'));
  console.log(c.grey(`    Razorpay Key ID : ${RAZORPAY_KEY_ID}`));
  console.log(c.grey(`    Plan ID         : ${RAZORPAY_PLAN_ID || '(not set — subscription test will be skipped)'}`));
  console.log(c.grey(`    Webhook secret  : ${'*'.repeat(Math.min(RAZORPAY_WEBHOOK_SECRET.length, 6))}... (${RAZORPAY_WEBHOOK_SECRET.length} chars)`));
  console.log(c.grey(`    Functions emulator : http://${FUNCTIONS_HOST}:${FUNCTIONS_PORT}`));
  console.log(c.grey(`    Firestore emulator : ${FIRESTORE_HOST}:${FIRESTORE_PORT}`));
  console.log(c.grey(`    Test business ID   : ${TEST_BIZ_ID}`));
  console.log(c.yellow(
    '\n  ⚠️   If the emulators were already running when functions/.secret.local was\n' +
    '       first written, RESTART the emulators so they load the secrets.\n' +
    '       Webhook will return 500 otherwise (secret value() returns empty string).'
  ));

  let testOrderId = null;    // set in Section A, used in Section C
  const results   = [];      // { name, passed }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION A — createOrder logic
  // ══════════════════════════════════════════════════════════════════════════

  section('SECTION A  createOrder — ₹1999 setup fee order (Razorpay Test API)');

  let order;
  try {
    info(`Calling razorpay.orders.create  amount=₹1999 receipt=${TEST_BIZ_ID}`);
    order = await razorpay.orders.create({
      amount:   199900,      // paise
      currency: 'INR',
      receipt:  TEST_BIZ_ID, // maps payment → business in the webhook handler
      notes: {
        businessId: TEST_BIZ_ID,
        type:       'setup_fee',
      },
    });

    console.log('\n  Razorpay response:');
    console.log(JSON.stringify(order, null, 4).split('\n').map(l => '  ' + l).join('\n'));

    if (order && order.id && order.status === 'created') {
      pass(`Order created:  id=${order.id}  status=${order.status}  amount=${order.amount} paise`);
      testOrderId = order.id;
      results.push({ name: 'createOrder', passed: true });
    } else {
      fail(`Unexpected order response — status=${order?.status}`);
      results.push({ name: 'createOrder', passed: false });
    }
  } catch (err) {
    fail(`razorpay.orders.create threw: ${err.message}`);
    console.error(err);
    results.push({ name: 'createOrder', passed: false });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION B — createSubscription logic
  // ══════════════════════════════════════════════════════════════════════════

  section('SECTION B  createSubscription — ₹999/year subscription (Razorpay Test API)');

  if (!RAZORPAY_PLAN_ID) {
    warn('RAZORPAY_PLAN_ID is not set. Skipping subscription test.');
    warn('Add RAZORPAY_PLAN_ID=plan_XXXXXXXXX to functions/.env.local and re-run.');
    results.push({ name: 'createSubscription', passed: null }); // skipped
  } else {
    let subscription;
    try {
      info(`Calling razorpay.subscriptions.create  plan_id=${RAZORPAY_PLAN_ID}`);
      subscription = await razorpay.subscriptions.create({
        plan_id:     RAZORPAY_PLAN_ID,
        total_count: 100,   // Razorpay maximum for yearly plans
        quantity:    1,
        notes: {
          businessId: TEST_BIZ_ID,
        },
      });

      console.log('\n  Razorpay response:');
      console.log(JSON.stringify(subscription, null, 4).split('\n').map(l => '  ' + l).join('\n'));

      if (subscription && subscription.id) {
        pass(`Subscription created:  id=${subscription.id}  status=${subscription.status}`);
        results.push({ name: 'createSubscription', passed: true });
      } else {
        fail(`Unexpected subscription response`);
        results.push({ name: 'createSubscription', passed: false });
      }
    } catch (err) {
      fail(`razorpay.subscriptions.create threw: ${err.message}`);
      if (err.error) {
        console.error('  Razorpay error details:', JSON.stringify(err.error, null, 4));
      }
      results.push({ name: 'createSubscription', passed: false });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION C — razorpayWebhook end-to-end (emulator)
  // ══════════════════════════════════════════════════════════════════════════

  section('SECTION C  razorpayWebhook — end-to-end via Firestore + Functions emulators');

  // ── C.1  Seed test business doc ───────────────────────────────────────────

  info(`Seeding business doc: businesses/${TEST_BIZ_ID}`);

  const yesterday  = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const gracePeriodEnds = new Date(Date.now() + 29 * 24 * 60 * 60 * 1000);

  const seedData = {
    brand_name:          'Test Business (test-doc-05)',
    category_type:       'restaurant',
    subscription_status: 'grace_period',       // starts in grace — webhook should flip to active
    renewal_date:        Timestamp.fromDate(yesterday),
    grace_period_ends:   Timestamp.fromDate(gracePeriodEnds),
    enrolled_by:         'emp_test_001',
    currently_managed_by:'emp_test_001',
  };

  try {
    await db.collection('businesses').doc(TEST_BIZ_ID).set(seedData);
    pass(`Seeded: businesses/${TEST_BIZ_ID}  status=${seedData.subscription_status}`);
  } catch (err) {
    fail(`Could not seed test business doc: ${err.message}`);
    console.error('  Hint: is the Firestore emulator running?');
    console.error(`  FIRESTORE_EMULATOR_HOST=${process.env['FIRESTORE_EMULATOR_HOST']}`);
    results.push({ name: 'webhook-seed', passed: false });
    // Can't continue without the doc.
    printSummary(results);
    process.exit(1);
  }

  // ── C.2  Build webhook payload ────────────────────────────────────────────

  // Use the real Razorpay test order ID from Section A if available;
  // otherwise use a placeholder.
  const orderIdForWebhook = testOrderId || `order_PLACEHOLDER_${Date.now()}`;

  const webhookPayload = {
    event:      'payment.captured',
    account_id: `acc_test`,
    contains:   ['payment'],
    payload: {
      payment: {
        entity: {
          id:          `pay_test_${Date.now()}`,
          order_id:    orderIdForWebhook,
          amount:      199900,
          currency:    'INR',
          status:      'captured',
          description: null,   // businessId comes from notes in this test
          notes: {
            businessId: TEST_BIZ_ID,
            type:       'setup_fee',
          },
          created_at:  Math.floor(Date.now() / 1000),
        },
      },
    },
  };

  const bodyStr  = JSON.stringify(webhookPayload);
  const signature = signWebhookPayload(bodyStr);

  info(`Webhook payload built:  event=payment.captured  businessId=${TEST_BIZ_ID}`);
  info(`Computed HMAC-SHA256 signature: ${signature.substring(0, 16)}…  (${signature.length} hex chars)`);

  // ── C.3  POST to local Functions emulator ─────────────────────────────────

  info(`POST  http://${FUNCTIONS_HOST}:${FUNCTIONS_PORT}${WEBHOOK_URL_PATH}`);

  let webhookResponse;
  try {
    webhookResponse = await httpPost(
      FUNCTIONS_HOST,
      FUNCTIONS_PORT,
      WEBHOOK_URL_PATH,
      bodyStr,
      { 'x-razorpay-signature': signature }
    );

    console.log(`\n  HTTP ${webhookResponse.status}  →  ${webhookResponse.body}`);

    if (webhookResponse.status === 200) {
      pass(`Webhook returned HTTP 200`);
      results.push({ name: 'webhook-http', passed: true });
    } else if (webhookResponse.status === 500) {
      fail(`Webhook returned HTTP 500 — function threw internally.`);
      console.log(c.yellow(
        '\n  ⚠️   Most common cause: the emulator was started BEFORE\n' +
        '       functions/.secret.local was written.\n' +
        '       Fix: stop the emulators, then restart:\n' +
        '         firebase emulators:start --only firestore,functions,hosting\n' +
        '       Then run this script again.'
      ));
      results.push({ name: 'webhook-http', passed: false });
    } else {
      fail(`Webhook returned HTTP ${webhookResponse.status} (expected 200)`);
      results.push({ name: 'webhook-http', passed: false });
    }
  } catch (err) {
    fail(`HTTP POST to webhook failed: ${err.message}`);
    console.error('\n  Hint: is the Functions emulator running?');
    console.error(`  Check: firebase emulators:start --only firestore,functions`);
    results.push({ name: 'webhook-http', passed: false });
    printSummary(results);
    process.exit(1);
  }

  // ── C.4  Reject test — bad signature should get HTTP 400 ─────────────────

  info(`Testing invalid signature → expect HTTP 400`);
  let badSigResp;
  try {
    badSigResp = await httpPost(
      FUNCTIONS_HOST,
      FUNCTIONS_PORT,
      WEBHOOK_URL_PATH,
      bodyStr,
      { 'x-razorpay-signature': 'badsignaturexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' }
    );
    if (badSigResp.status === 400) {
      pass(`Bad signature correctly rejected: HTTP 400`);
      results.push({ name: 'webhook-bad-signature', passed: true });
    } else {
      fail(`Bad signature returned HTTP ${badSigResp.status} — expected 400 (security issue!)`);
      results.push({ name: 'webhook-bad-signature', passed: false });
    }
  } catch (err) {
    fail(`Bad-signature test POST failed: ${err.message}`);
    results.push({ name: 'webhook-bad-signature', passed: false });
  }

  // ── C.5  Read back Firestore state ────────────────────────────────────────

  info(`Waiting 2 s for function to commit to Firestore emulator…`);
  await sleep(2000);

  let bizSnap;
  try {
    bizSnap = await db.collection('businesses').doc(TEST_BIZ_ID).get();
  } catch (err) {
    fail(`Could not read back business doc: ${err.message}`);
    results.push({ name: 'webhook-firestore-status', passed: false });
    results.push({ name: 'webhook-firestore-renewal', passed: false });
    printSummary(results);
    process.exit(1);
  }

  if (!bizSnap.exists) {
    fail(`Business doc ${TEST_BIZ_ID} was deleted or never created!`);
    results.push({ name: 'webhook-firestore-status',  passed: false });
    results.push({ name: 'webhook-firestore-renewal', passed: false });
    printSummary(results);
    process.exit(1);
  }

  const bizData = bizSnap.data();
  console.log('\n  Updated business doc fields:');
  console.log(`  subscription_status : ${c.bold(bizData.subscription_status)}`);
  console.log(`  renewal_date        : ${bizData.renewal_date?.toDate?.()?.toISOString() ?? bizData.renewal_date}`);
  console.log(`  grace_period_ends   : ${bizData.grace_period_ends ?? c.green('(field removed ✓)')}`);

  // Assert subscription_status === 'active'
  if (bizData.subscription_status === 'active') {
    pass(`subscription_status = "active"  ✓`);
    results.push({ name: 'webhook-firestore-status', passed: true });
  } else {
    fail(`subscription_status = "${bizData.subscription_status}" (expected "active")`);
    results.push({ name: 'webhook-firestore-status', passed: false });
  }

  // Assert renewal_date is approximately 1 year from now.
  const renewalDate = bizData.renewal_date?.toDate?.();
  if (renewalDate) {
    const oneYearFromNow   = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
    const toleranceMs      = 5 * 60 * 1000; // 5-minute tolerance
    const diff             = Math.abs(renewalDate.getTime() - oneYearFromNow.getTime());
    if (diff <= toleranceMs) {
      pass(`renewal_date ≈ 1 year from now  (${renewalDate.toISOString()})  ✓`);
      results.push({ name: 'webhook-firestore-renewal', passed: true });
    } else {
      fail(`renewal_date ${renewalDate.toISOString()} is not ~1 year from now`);
      results.push({ name: 'webhook-firestore-renewal', passed: false });
    }
  } else {
    fail(`renewal_date field is missing or not a Firestore Timestamp`);
    results.push({ name: 'webhook-firestore-renewal', passed: false });
  }

  // Assert grace_period_ends was cleared.
  if (!bizData.grace_period_ends) {
    pass(`grace_period_ends field was cleared  ✓`);
    results.push({ name: 'webhook-grace-cleared', passed: true });
  } else {
    fail(`grace_period_ends is still set: ${bizData.grace_period_ends}`);
    results.push({ name: 'webhook-grace-cleared', passed: false });
  }

  // ── C.6  Confirm commission_records doc created ───────────────────────────

  info(`Checking commission_records for business ${TEST_BIZ_ID}…`);
  let commSnap;
  try {
    commSnap = await db
      .collection('commission_records')
      .where('business_id', '==', TEST_BIZ_ID)
      .orderBy('date_claimed', 'desc')
      .limit(1)
      .get();
  } catch (err) {
    fail(`commission_records query failed: ${err.message}`);
    results.push({ name: 'commission-record', passed: false });
    printSummary(results);
    process.exit(1);
  }

  if (commSnap.empty) {
    fail(`No commission_records entry was created for business ${TEST_BIZ_ID}`);
    results.push({ name: 'commission-record', passed: false });
  } else {
    const comm = commSnap.docs[0].data();
    console.log('\n  commission_records entry:');
    console.log(`  employee_id  : ${comm.employee_id}`);
    console.log(`  amount       : ₹${comm.amount}`);
    console.log(`  payment_mode : ${comm.payment_mode}`);
    console.log(`  status       : ${comm.status}`);
    console.log(`  date_claimed : ${comm.date_claimed?.toDate?.()?.toISOString()}`);

    const isCorrect =
      comm.payment_mode === 'online' &&
      comm.status       === 'verified' &&
      comm.employee_id  === seedData.enrolled_by;

    if (isCorrect) {
      pass(`commission_records created: payment_mode=online  status=verified  employee_id=${comm.employee_id}  ✓`);
      results.push({ name: 'commission-record', passed: true });
    } else {
      fail(
        `commission_records values unexpected:\n` +
        `  payment_mode=${comm.payment_mode} (want online)\n` +
        `  status=${comm.status} (want verified)\n` +
        `  employee_id=${comm.employee_id} (want ${seedData.enrolled_by})`
      );
      results.push({ name: 'commission-record', passed: false });
    }
  }

  // ─── Summary ─────────────────────────────────────────────────────────────

  printSummary(results);
}

// ─── Summary printer ─────────────────────────────────────────────────────────

function printSummary(results) {
  section('TEST SUMMARY');
  let passCount = 0, failCount = 0, skipCount = 0;
  for (const r of results) {
    if (r.passed === true)  { pass(`PASS  ${r.name}`);            passCount++; }
    else if (r.passed === false) { fail(`FAIL  ${r.name}`);       failCount++; }
    else                    { warn(`SKIP  ${r.name} (no data)`);  skipCount++; }
  }
  console.log('');
  const total = passCount + failCount + skipCount;
  if (failCount === 0) {
    console.log(c.bold(c.green(`  🎉  ALL ${passCount}/${total} TESTS PASSED`)));
  } else {
    console.log(c.bold(c.red(`  ❌  ${failCount} FAILED  /  ${passCount} PASSED  /  ${skipCount} SKIPPED  (${total} total)`)));
  }
  console.log('');
  process.exitCode = failCount > 0 ? 1 : 0;
}

// ─── Run ─────────────────────────────────────────────────────────────────────

main().catch((err) => {
  console.error('\n💥  Unexpected fatal error:', err);
  process.exit(1);
});
