#!/usr/bin/env node
/**
 * scripts/test-doc-08.js
 *
 * Local integration test for the Notifications System (doc 08).
 *
 * What it does:
 *   1. Reads BREVO_API_KEY, ADMIN_EMAIL, BREVO_SENDER_EMAIL from
 *      functions/.secret.local and functions/.env.local.
 *   2. Seeds a test business with renewal_date = today + 30 days
 *      and a real owner_email into the Firestore emulator.
 *   3. Seeds a test employee doc with a real contact email.
 *   4. Triggers the sendRenewalReminders-0 scheduled function via
 *      HTTP POST to the local Functions emulator.
 *   5. Reads back the notifications collection and prints what was
 *      written — tells you exactly what to verify in your inbox and
 *      the Brevo dashboard.
 *
 * Prerequisites:
 *   - Firebase emulators running:
 *       firebase emulators:start --only firestore,functions,hosting
 *   - functions/.secret.local contains BREVO_API_KEY=xkeysib-...
 *   - functions/.env.local contains real ADMIN_EMAIL and
 *     BREVO_SENDER_EMAIL values (not the placeholders).
 *   - The emulators were started AFTER .secret.local was written.
 *
 * Usage (from repo root):
 *   node scripts/test-doc-08.js
 *
 * For the weekly admin digest, trigger manually:
 *   curl -X POST \
 *     http://127.0.0.1:5001/review-system-prod-49b7a/asia-south1/sendAdminDigest-0 \
 *     -H "Content-Type: application/json" -d '{}'
 */

"use strict";

const fs   = require("fs");
const path = require("path");
const http = require("http");

// ─── Colours ────────────────────────────────────────────────────────────────
const c = {
  green:  (s) => `\x1b[32m${s}\x1b[0m`,
  red:    (s) => `\x1b[31m${s}\x1b[0m`,
  yellow: (s) => `\x1b[33m${s}\x1b[0m`,
  cyan:   (s) => `\x1b[36m${s}\x1b[0m`,
  grey:   (s) => `\x1b[90m${s}\x1b[0m`,
  bold:   (s) => `\x1b[1m${s}\x1b[0m`,
};

// ─── Config ─────────────────────────────────────────────────────────────────
const FUNCTIONS_HOST    = "127.0.0.1";
const FUNCTIONS_PORT    = 5001;
const FIRESTORE_HOST    = "127.0.0.1";
const FIRESTORE_PORT    = 8080;
const FIREBASE_PROJECT  = "review-system-prod-49b7a";
const TEST_BIZ_ID       = "notif-test-biz-001";
const TEST_EMP_ID       = "notif-test-emp-001";
const REGION            = "asia-south1";

// ─── Read .secret.local ──────────────────────────────────────────────────────
function readLocalFile(filePath) {
  try {
    const content = fs.readFileSync(
      path.join(__dirname, "..", filePath), "utf8"
    );
    const result = {};
    content.split("\n").forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) return;
      const eq = trimmed.indexOf("=");
      if (eq === -1) return;
      result[trimmed.slice(0, eq).trim()] =
        trimmed.slice(eq + 1).trim();
    });
    return result;
  } catch {
    return {};
  }
}

const secrets = readLocalFile("functions/.secret.local");
const params  = readLocalFile("functions/.env.local");

const BREVO_API_KEY      = secrets.BREVO_API_KEY || "";
const ADMIN_EMAIL        = params.ADMIN_EMAIL || "";
const BREVO_SENDER_EMAIL = params.BREVO_SENDER_EMAIL || "";

// ─── Helpers ─────────────────────────────────────────────────────────────────
let passed = 0;
let failed = 0;
const results = [];

function pass(msg) {
  console.log(c.green("  ✅ " + msg));
  passed++;
  results.push({ msg, ok: true });
}
function fail(msg) {
  console.log(c.red("  ❌ " + msg));
  failed++;
  results.push({ msg, ok: false });
}

function httpPost(host, port, path_, body) {
  return new Promise((resolve, reject) => {
    const data = typeof body === "string" ? body : JSON.stringify(body);
    const req = http.request(
      {
        hostname: host, port, method: "POST", path: path_,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(data),
        },
      },
      (res) => {
        let raw = "";
        res.on("data", (c_) => (raw += c_));
        res.on("end", () =>
          resolve({ status: res.statusCode, body: raw })
        );
      }
    );
    req.on("error", reject);
    req.write(data);
    req.end();
  });
}

async function firestoreGet(collection, docId) {
  const url = `http://${FIRESTORE_HOST}:${FIRESTORE_PORT}` +
    `/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents` +
    `/${collection}/${docId}`;
  const res = await fetch(url);
  if (res.status === 404) return null;
  return res.json();
}

async function firestoreSet(collection, docId, fields) {
  // PATCH to the document path creates or overwrites the document.
  // POST would create a new document with an auto-generated ID.
  const url = `http://${FIRESTORE_HOST}:${FIRESTORE_PORT}` +
    `/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents` +
    `/${collection}/${docId}`;
  const res = await fetch(url, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "(unreadable)");
    throw new Error(
      `Firestore PATCH failed ${res.status}: ${text.slice(0, 200)}`
    );
  }
}

async function firestoreList(collection) {
  const url = `http://${FIRESTORE_HOST}:${FIRESTORE_PORT}` +
    `/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents` +
    `/${collection}`;
  const res = await fetch(url);
  const data = await res.json();
  return data.documents || [];
}

async function firestoreDelete(collection, docId) {
  const url = `http://${FIRESTORE_HOST}:${FIRESTORE_PORT}` +
    `/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents` +
    `/${collection}/${docId}`;
  await fetch(url, { method: "DELETE" });
}

function ts(date) {
  return {
    timestampValue: date.toISOString(),
  };
}

// ─── Main ────────────────────────────────────────────────────────────────────
async function main() {
  console.log(c.bold("\n╔══════════════════════════════════════════╗"));
  console.log(c.bold("║  Doc 08 — Notifications Integration Test ║"));
  console.log(c.bold("╚══════════════════════════════════════════╝\n"));

  // ─── Pre-flight checks ────────────────────────────────────────────
  console.log(c.cyan("─── Pre-flight checks ───────────────────────────\n"));
  console.log(c.grey(`  BREVO_API_KEY    : ${
    BREVO_API_KEY ?
      BREVO_API_KEY.slice(0, 12) + "…" :
      "(not set)"
  }`));
  console.log(c.grey(`  ADMIN_EMAIL      : ${ADMIN_EMAIL || "(not set)"}`));
  console.log(c.grey(`  BREVO_SENDER_EMAIL: ${
    BREVO_SENDER_EMAIL || "(not set)"
  }`));

  if (!BREVO_API_KEY) {
    console.log(c.red(
      "\n  ❌ BREVO_API_KEY missing from functions/.secret.local\n" +
      "     Add: BREVO_API_KEY=xkeysib-...\n" +
      "     Then RESTART the emulators.\n"
    ));
    process.exit(1);
  }

  const isOwnerEmailPlaceholder =
    !ADMIN_EMAIL || ADMIN_EMAIL.includes("example.com");
  if (isOwnerEmailPlaceholder) {
    console.log(c.yellow(
      "\n  ⚠️  ADMIN_EMAIL is placeholder. Update functions/.env.local" +
      " with a real address\n     and restart emulators to receive the" +
      " weekly digest email.\n"
    ));
  }

  // ─── Section A: Seed test data ────────────────────────────────────
  console.log(c.cyan("\n─── A: Seed test data ───────────────────────────\n"));

  // Business: renewal 30 days from today
  const in30 = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const ownerTestEmail = ADMIN_EMAIL ||
    "test-owner@example.com";

  await firestoreSet("businesses", TEST_BIZ_ID, {
    brand_name:            { stringValue: "Notif Test Café" },
    category_type:         { stringValue: "cafe" },
    subscription_status:   { stringValue: "active" },
    renewal_date:          ts(in30),
    owner_email:           { stringValue: ownerTestEmail },
    currently_managed_by:  { stringValue: TEST_EMP_ID },
    enrolled_by:           { stringValue: TEST_EMP_ID },
    logo_url:              { stringValue: "" },
  });

  // Employee: use ADMIN_EMAIL as contact so we get the email
  await firestoreSet("employees", TEST_EMP_ID, {
    name:    { stringValue: "Test Employee" },
    contact: { stringValue: ownerTestEmail },
    role:    { stringValue: "employee" },
    active:  { booleanValue: true },
  });

  console.log(c.grey(
    `  Business : ${TEST_BIZ_ID} (renewal_date = ${in30.toDateString()})`
  ));
  console.log(c.grey(`  Employee : ${TEST_EMP_ID}`));
  console.log(c.grey(`  Emails   : ${ownerTestEmail}`));
  pass("Test data seeded into Firestore emulator");

  // ─── Section B: Count notifications before ────────────────────────
  const beforeDocs = await firestoreList("notifications");
  const beforeCount = beforeDocs.length;
  console.log(c.grey(
    `\n  notifications collection before: ${beforeCount} docs`
  ));

  // ─── Section C: Trigger sendRenewalReminders ──────────────────────
  console.log(c.cyan(
    "\n─── B: Trigger sendRenewalReminders ─────────────────\n"
  ));

  const fnPath =
    `/${FIREBASE_PROJECT}/${REGION}/sendRenewalReminders-0`;
  let triggerResponse;
  try {
    triggerResponse = await httpPost(
      FUNCTIONS_HOST, FUNCTIONS_PORT, fnPath, "{}"
    );
  } catch (err) {
    fail(`Cannot reach Functions emulator: ${err.message}`);
    console.log(c.red(
      "  Ensure emulators are running:\n" +
      "    firebase emulators:start --only firestore,functions,hosting\n"
    ));
    process.exit(1);
  }

  console.log(c.grey(
    `  Function response: HTTP ${triggerResponse.status}`
  ));

  if (triggerResponse.status === 200) {
    pass("sendRenewalReminders returned HTTP 200");
  } else if (triggerResponse.status === 500) {
    fail("HTTP 500 — function threw. Most likely cause:");
    console.log(c.yellow(
      "  • Emulators were started BEFORE functions/.secret.local\n" +
      "    was written (BREVO_API_KEY not loaded).\n" +
      "  • Fix: stop emulators → restart → re-run this script.\n"
    ));
    process.exit(1);
  } else {
    fail(`Unexpected HTTP ${triggerResponse.status}`);
  }

  // Give Firestore writes a moment to propagate in the emulator
  await new Promise((r) => setTimeout(r, 1500));

  // ─── Section D: Verify notifications written ──────────────────────
  console.log(c.cyan(
    "\n─── C: Verify notifications in Firestore ────────────\n"
  ));

  const afterDocs = await firestoreList("notifications");
  const newDocs = afterDocs.slice(beforeCount);

  console.log(c.grey(
    `  notifications collection after: ${afterDocs.length} docs` +
    ` (${newDocs.length} new)`
  ));

  if (newDocs.length >= 2) {
    pass(
      `${newDocs.length} notification doc(s) written ` +
      "(expected ≥ 2: owner + employee)"
    );
  } else if (newDocs.length === 1) {
    pass("1 notification doc written (owner email only — check employee contact)");
  } else {
    fail(
      "No new notifications written. " +
      "Check function logs in the emulator terminal."
    );
  }

  // Print what was written
  newDocs.forEach((doc, i) => {
    const f = doc.fields || {};
    console.log(c.grey(
      `\n  [${i + 1}] ` +
      `recipient=${f.recipient?.stringValue || "?"} ` +
      `role=${f.recipient_role?.stringValue || "?"} ` +
      `type=${f.type?.stringValue || "?"}`
    ));
    console.log(c.grey(
      `      message: "${(f.message?.stringValue || "").slice(0, 80)}"`
    ));
    console.log(c.grey(
      `      read: ${f.read?.booleanValue ?? "?"}`
    ));
  });

  const hasOwnerNotif = newDocs.some(
    (d) => d.fields?.recipient_role?.stringValue === "owner"
  );
  const hasEmployeeNotif = newDocs.some(
    (d) => d.fields?.recipient_role?.stringValue === "employee"
  );
  const allReadFalse = newDocs.every(
    (d) => d.fields?.read?.booleanValue === false
  );
  const correctType = newDocs.some(
    (d) => d.fields?.type?.stringValue === "renewal_reminder_30"
  );

  if (hasOwnerNotif) pass("Owner notification doc present");
  else fail("Owner notification doc missing");

  if (hasEmployeeNotif) pass("Employee notification doc present");
  else fail("Employee notification doc missing — check employee.contact is an email");

  if (allReadFalse) pass("All notification docs have read: false");
  else fail("Some docs have read != false");

  if (correctType) pass("type = 'renewal_reminder_30' (correct window)");
  else fail("type field missing or wrong value");

  // ─── Section E: Idempotency check ────────────────────────────────
  console.log(c.cyan(
    "\n─── D: Idempotency — trigger again (should skip) ────\n"
  ));

  await httpPost(FUNCTIONS_HOST, FUNCTIONS_PORT, fnPath, "{}");
  await new Promise((r) => setTimeout(r, 1500));

  const afterAgainDocs = await firestoreList("notifications");
  const afterAgainNew = afterAgainDocs.length - afterDocs.length;
  console.log(c.grey(
    `  New docs on 2nd trigger: ${afterAgainNew}`
  ));

  if (afterAgainNew === 0) {
    pass("Idempotency works — no duplicate notifications sent");
  } else {
    fail(
      `Idempotency failed — ${afterAgainNew} duplicate(s) written`
    );
  }

  // ─── Section F: Cleanup ────────────────────────────────────────────
  console.log(c.cyan("\n─── E: Cleanup ─────────────────────────────────\n"));
  await firestoreDelete("businesses", TEST_BIZ_ID);
  await firestoreDelete("employees",  TEST_EMP_ID);
  console.log(c.grey("  Test documents removed."));

  // ─── Summary ──────────────────────────────────────────────────────
  const total = passed + failed;
  console.log(c.bold(
    `\n╔══════════════════════════════════════════════════════╗`
  ));
  console.log(c.bold(
    `║  Results: ${passed}/${total} passed` +
    `${" ".repeat(41 - String(passed).length - String(total).length)}║`
  ));
  console.log(c.bold(
    `╚══════════════════════════════════════════════════════╝`
  ));

  if (failed === 0) {
    console.log(c.green(
      "\n  🎉 All checks passed!\n"
    ));
    console.log(
      "  Now verify externally:\n" +
      `  1. Brevo dashboard → Transactional → Logs:\n` +
      `     look for emails to ${ownerTestEmail}\n` +
      `  2. Check your inbox for subject:\n` +
      `     "Renewal in 30 days — Notif Test Café"\n` +
      `  3. For the weekly digest, trigger:\n` +
      `     curl -X POST \\\n` +
      `       http://127.0.0.1:5001/${FIREBASE_PROJECT}/${REGION}` +
      `/sendAdminDigest-0 \\\n` +
      `       -H "Content-Type: application/json" -d '{}'\n`
    );
  } else {
    console.log(c.red(
      `\n  ${failed} check(s) failed. See above for details.\n`
    ));
  }

  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(c.red("\nUnhandled error:"), err);
  process.exit(1);
});
