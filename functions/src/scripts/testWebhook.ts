/**
 * scripts/testWebhook.ts
 *
 * Emulator test script for the razorpayWebhook Cloud Function.
 *
 * Usage:
 *   1. Start the emulators:
 *        firebase emulators:start --only functions,firestore
 *   2. In a second terminal, seed a business doc and run this script:
 *        npx ts-node --project tsconfig.scripts.json src/scripts/testWebhook.ts
 *
 * The script:
 *   a) Seeds a test business document into the Firestore emulator.
 *   b) Constructs a signed `payment.captured` webhook payload using the
 *      webhook secret stored in RAZORPAY_WEBHOOK_SECRET_TEST env var
 *      (or a default test secret for local testing only).
 *   c) POSTs the payload to the local Functions emulator.
 *   d) Reads the updated business doc and commission_records to confirm
 *      the webhook handler applied the correct state changes.
 *
 * Environment variables (optional — defaults work with emulator):
 *   FIRESTORE_EMULATOR_HOST      default: 127.0.0.1:8080
 *   FUNCTIONS_EMULATOR_HOST      default: 127.0.0.1:5001
 *   RAZORPAY_WEBHOOK_SECRET_TEST default: "test_webhook_secret_local"
 *   TEST_BUSINESS_ID             default: "biz_test_001"
 *
 * NOTE: This script uses its own Firestore Admin init pointed at the emulator.
 *       It does NOT share the production Admin instance from index.ts.
 */

import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as http from "http";

// ── Configuration ─────────────────────────────────────────────────────────────

const FIRESTORE_HOST = process.env["FIRESTORE_EMULATOR_HOST"] ?? "127.0.0.1:8080";
const FUNCTIONS_HOST = process.env["FUNCTIONS_EMULATOR_HOST"] ?? "127.0.0.1:5001";
const FIREBASE_PROJECT = process.env["GCLOUD_PROJECT"] ?? "review-system-prod-49b7a";

// Use a test-only webhook secret. In production the real secret is in Secret Manager.
// This value must also be what you set in RAZORPAY_WEBHOOK_SECRET when running
// the emulator (or the function will reject the signature).
const WEBHOOK_SECRET =
  process.env["RAZORPAY_WEBHOOK_SECRET_TEST"] ?? "test_webhook_secret_local";

const BUSINESS_ID = process.env["TEST_BUSINESS_ID"] ?? "biz_test_001";

// ── Init Admin SDK pointing at emulator ───────────────────────────────────────

process.env["FIRESTORE_EMULATOR_HOST"] = FIRESTORE_HOST;

if (!admin.apps.length) {
  admin.initializeApp({projectId: FIREBASE_PROJECT});
}
const db = admin.firestore();

// ── Helpers ───────────────────────────────────────────────────────────────────

function sign(body: string): string {
  return crypto.createHmac("sha256", WEBHOOK_SECRET).update(body).digest("hex");
}

function post(
  host: string,
  port: number,
  path: string,
  body: string,
  signature: string
): Promise<{status: number; body: string}> {
  return new Promise((resolve, reject) => {
    const options: http.RequestOptions = {
      hostname: host,
      port,
      path,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
        "X-Razorpay-Signature": signature,
      },
    };
    const req = http.request(options, (res) => {
      let data = "";
      res.on("data", (chunk: string) => (data += chunk));
      res.on("end", () => resolve({status: res.statusCode ?? 0, body: data}));
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log("\n🔧  Razorpay Webhook Emulator Test");
  console.log(`   Firestore:  ${FIRESTORE_HOST}`);
  console.log(`   Functions:  ${FUNCTIONS_HOST}`);
  console.log(`   Business:   ${BUSINESS_ID}\n`);

  // 1. Seed test business doc ────────────────────────────────────────────────
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);

  await db.collection("businesses").doc(BUSINESS_ID).set({
    brand_name: "Test Business (webhook test)",
    subscription_status: "grace_period",
    renewal_date: admin.firestore.Timestamp.fromDate(yesterday),
    grace_period_ends: admin.firestore.Timestamp.fromDate(
      new Date(yesterday.getTime() + 30 * 24 * 60 * 60 * 1000)
    ),
    enrolled_by: "emp_test_001",
    category_type: "restaurant",
  });
  console.log(`✅  Seeded business doc: ${BUSINESS_ID}`);

  // 2. Build signed payment.captured payload ─────────────────────────────────
  const payload = {
    event: "payment.captured",
    payload: {
      payment: {
        entity: {
          id: `pay_test_${Date.now()}`,
          order_id: `order_test_${Date.now()}`,
          amount: 199900,
          currency: "INR",
          status: "captured",
          notes: {
            businessId: BUSINESS_ID,
            type: "setup_fee",
          },
        },
      },
    },
  };

  const body = JSON.stringify(payload);
  const signature = sign(body);

  // 3. POST to emulator ───────────────────────────────────────────────────────
  const [host, portStr] = FUNCTIONS_HOST.split(":");
  const port = parseInt(portStr ?? "5001", 10);
  const path = `/${FIREBASE_PROJECT}/asia-south1/razorpayWebhook`;

  console.log(`📤  POST ${FUNCTIONS_HOST}${path}`);
  console.log(`   Signature: ${signature.substring(0, 16)}…\n`);

  const response = await post(host, port, path, body, signature);
  console.log(`📥  HTTP ${response.status}: ${response.body}`);

  if (response.status !== 200) {
    console.error("\n❌  Webhook returned non-200. Check function logs.");
    process.exit(1);
  }

  // 4. Verify Firestore state ────────────────────────────────────────────────
  // Give the function a moment to commit.
  await new Promise((r) => setTimeout(r, 1500));

  const bizSnap = await db.collection("businesses").doc(BUSINESS_ID).get();
  const bizData = bizSnap.data();
  console.log("\n📄  Updated business doc:");
  console.log(`   subscription_status : ${bizData?.["subscription_status"]}`);
  console.log(`   renewal_date        : ${bizData?.["renewal_date"]?.toDate().toISOString()}`);
  console.log(`   grace_period_ends   : ${bizData?.["grace_period_ends"] ?? "(cleared ✓)"}`);

  if (bizData?.["subscription_status"] !== "active") {
    console.error("\n❌  FAIL: subscription_status was not set to 'active'");
    process.exit(1);
  }

  // 5. Verify commission_records ─────────────────────────────────────────────
  const commSnap = await db
    .collection("commission_records")
    .where("business_id", "==", BUSINESS_ID)
    .orderBy("date_claimed", "desc")
    .limit(1)
    .get();

  if (commSnap.empty) {
    console.error("\n❌  FAIL: no commission_records entry created");
    process.exit(1);
  }

  const commData = commSnap.docs[0].data();
  console.log("\n📄  Commission record:");
  console.log(`   employee_id   : ${commData["employee_id"]}`);
  console.log(`   amount        : ₹${commData["amount"]}`);
  console.log(`   payment_mode  : ${commData["payment_mode"]}`);
  console.log(`   status        : ${commData["status"]}`);

  if (commData["payment_mode"] !== "online" || commData["status"] !== "verified") {
    console.error("\n❌  FAIL: commission record has wrong payment_mode or status");
    process.exit(1);
  }

  console.log("\n✅  ALL ASSERTIONS PASSED\n");

  // 6. Test invalid signature (should return 400) ────────────────────────────
  console.log("🔒  Testing invalid signature (expect HTTP 400)…");
  const badResp = await post(
    host, port, path, body, "badsignaturethatisnotvalid"
  );
  if (badResp.status !== 400) {
    console.error(`❌  FAIL: expected 400 for bad signature, got ${badResp.status}`);
    process.exit(1);
  }
  console.log("✅  Invalid signature correctly rejected with HTTP 400\n");

  // 7. Test renewalLifecycle manually via Firestore data ────────────────────
  console.log(
    "📅  Seeding test data for renewalLifecycle simulation…"
  );

  // Business that should transition: active → grace_period
  const bizGrace = `biz_grace_test_${Date.now()}`;
  const twoDaysAgo = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000);
  await db.collection("businesses").doc(bizGrace).set({
    brand_name: "Grace Period Test Biz",
    subscription_status: "active",
    renewal_date: admin.firestore.Timestamp.fromDate(twoDaysAgo),
    enrolled_by: "emp_test_001",
  });

  // Business that should transition: grace_period → deleted
  const bizDelete = `biz_delete_test_${Date.now()}`;
  const thirtyTwoDaysAgo = new Date(Date.now() - 32 * 24 * 60 * 60 * 1000);
  await db.collection("businesses").doc(bizDelete).set({
    brand_name: "Deletion Test Biz",
    subscription_status: "grace_period",
    renewal_date: admin.firestore.Timestamp.fromDate(thirtyTwoDaysAgo),
    grace_period_ends: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 2 * 24 * 60 * 60 * 1000)
    ),
    enrolled_by: "emp_test_001",
  });

  // Add a branch and scan_log for the deletion test biz.
  const branchRef = db
    .collection("businesses")
    .doc(bizDelete)
    .collection("branches")
    .doc("branch_001");
  await branchRef.set({branch_name: "Main Branch", address: "Test St"});
  await db.collection("scan_logs").doc("scan_001").set({
    branch_id: "branch_001",
    star_rating: 5,
    timestamp: admin.firestore.Timestamp.now(),
  });

  // Add a commission_record — MUST NOT be deleted.
  await db.collection("commission_records").doc("comm_audit_001").set({
    employee_id: "emp_test_001",
    business_id: bizDelete,
    amount: 999,
    payment_mode: "online",
    status: "verified",
    date_claimed: admin.firestore.Timestamp.now(),
    date_verified: admin.firestore.Timestamp.now(),
  });

  console.log(`   Created ${bizGrace} (active, renewal_date 2 days ago)`);
  console.log(`   Created ${bizDelete} (grace_period, grace_period_ends 2 days ago)`);
  console.log("\n   Now trigger renewalLifecycle in the Functions emulator shell:");
  console.log("   firebase functions:shell");
  console.log("   > renewalLifecycle()");
  console.log("\n   Then verify in the emulator UI (http://127.0.0.1:4000):");
  console.log(`   • ${bizGrace} → subscription_status = "grace_period"`);
  console.log(`   • ${bizDelete} → document deleted`);
  console.log("   • commission_records/comm_audit_001 → still exists ✓");
  console.log("   • scan_logs/scan_001 → deleted ✓");
  console.log("   • businesses/biz_delete_test_.../branches/branch_001 → deleted ✓\n");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
