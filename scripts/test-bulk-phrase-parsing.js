/**
 * test-bulk-phrase-parsing.js
 *
 * Verifies bulk phrase parsing, division, and Firestore persistence:
 * 1. StringUtils.parseBulkPhrases parsing edge cases (bullets, numbering, semicolons, quotes).
 * 2. Bulk addition of phrases into Firestore category templates.
 * 3. Adding a new category with bulk phrases.
 */

const assert = require('assert');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const app = initializeApp({ projectId: 'review-system-prod-49b7a' });
const db = getFirestore(app);

// Mirror of StringUtils.parseBulkPhrases & collapseWhitespace
function collapseWhitespace(input) {
  if (!input) return '';
  return input.trim().replace(/\s+/g, ' ');
}

function parseBulkPhrases(rawText) {
  if (!rawText || !rawText.trim()) return [];

  const lines = rawText.split(/[\r\n]+/);
  const rawChunks = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (trimmed.includes(';')) {
      rawChunks.push(...trimmed.split(';'));
    } else {
      rawChunks.push(trimmed);
    }
  }

  const results = [];
  const seen = new Set();

  for (const chunk of rawChunks) {
    let p = chunk.trim();
    if (!p) continue;

    // Strip leading list numbers: "1. ", "1) ", "(1) ", "1 - "
    p = p.replace(/^\s*\(?\d+[\.\)\-\:]\s*/, '');

    // Strip leading bullet symbols: "- ", "* ", "• ", "– ", "— ", "> "
    p = p.replace(/^\s*[\-\*\•\–\—\>\#\+]\s*/, '');

    // Strip enclosing quotes: "Hello" -> Hello
    if ((p.startsWith('"') && p.endsWith('"')) || (p.startsWith("'") && p.endsWith("'"))) {
      if (p.length >= 2) {
        p = p.substring(1, p.length - 1).trim();
      }
    }

    p = collapseWhitespace(p);
    if (p.length > 0 && !seen.has(p.toLowerCase())) {
      seen.add(p.toLowerCase());
      results.add ? results.push(p) : results.push(p);
    }
  }

  return results;
}

async function runTest() {
  console.log('🧪 Starting Bulk Phrase Parsing & Division Test Suite...\n');

  // Test 1: Numbered and bulleted list parsing
  console.log('--- TEST 1: Numbered & Bulleted Multi-Line Parsing ---');
  const rawInput1 = `
    1. Freshly baked artisan breads and croissants!
    2) Delicious cakes with perfect sweetness.
    - Cozy ambiance with wonderful coffee aromas.
    • Polite and extremely attentive staff members.
    "Loved the chocolate walnut brownie!"
  `;

  const parsed1 = parseBulkPhrases(rawInput1);
  console.log('Parsed phrases:', parsed1);
  assert.strictEqual(parsed1.length, 5);
  assert.strictEqual(parsed1[0], 'Freshly baked artisan breads and croissants!');
  assert.strictEqual(parsed1[1], 'Delicious cakes with perfect sweetness.');
  assert.strictEqual(parsed1[2], 'Cozy ambiance with wonderful coffee aromas.');
  assert.strictEqual(parsed1[3], 'Polite and extremely attentive staff members.');
  assert.strictEqual(parsed1[4], 'Loved the chocolate walnut brownie!');
  console.log('✅ PASS: Numbered lists, bullets, and quotes cleanly stripped and divided.');

  // Test 2: Semicolon-separated single-line pasting
  console.log('\n--- TEST 2: Semicolon-Separated Bulk Pasting ---');
  const rawInput2 = 'Fast home delivery; Amazing packaging; Fresh hot food ; Affordable daily meals';
  const parsed2 = parseBulkPhrases(rawInput2);
  console.log('Parsed phrases:', parsed2);
  assert.strictEqual(parsed2.length, 4);
  assert.strictEqual(parsed2[0], 'Fast home delivery');
  assert.strictEqual(parsed2[1], 'Amazing packaging');
  assert.strictEqual(parsed2[2], 'Fresh hot food');
  assert.strictEqual(parsed2[3], 'Affordable daily meals');
  console.log('✅ PASS: Semicolon separation correctly divides single paste into 4 phrases.');

  // Test 3: Deduplication and excess whitespace collapsing
  console.log('\n--- TEST 3: Deduplication & Whitespace Normalization ---');
  const rawInput3 = `
    Great    customer     service!
    1. great customer service!
    2. GREAT CUSTOMER SERVICE!
    * Quick turnaround time
  `;
  const parsed3 = parseBulkPhrases(rawInput3);
  console.log('Parsed phrases:', parsed3);
  assert.strictEqual(parsed3.length, 2);
  assert.strictEqual(parsed3[0], 'Great customer service!');
  assert.strictEqual(parsed3[1], 'Quick turnaround time');
  console.log('✅ PASS: Case-insensitive duplicates collapsed, internal spaces normalized.');

  // Test 4: Firestore Template Creation with Bulk Phrases
  console.log('\n--- TEST 4: Firestore Template Creation & Bulk Category Addition ---');
  const templateId = 'bulk_test_template_v1';
  const tRef = db.collection('category_templates').doc(templateId);

  // 1. Create Template with 5 initial phrases
  await tRef.set({
    business_type: 'Cafe & Bistro',
    categories: [
      {
        name: 'Beverages & Coffee',
        phrase_pool: parsed1,
        phrase_pool_versions: {
          v1: parsed1,
        },
      }
    ],
    created_at: new Date(),
  });

  // 2. Add New Category with 4 phrases
  const snap1 = await tRef.get();
  const cats = snap1.data().categories;
  cats.push({
    name: 'Food & Quick Bites',
    phrase_pool: parsed2,
    phrase_pool_versions: {
      v1: parsed2,
    },
  });
  await tRef.update({ categories: cats });

  // 3. Verify in Firestore
  const verifySnap = await tRef.get();
  const verifyData = verifySnap.data();
  assert.strictEqual(verifyData.categories.length, 2);
  assert.strictEqual(verifyData.categories[0].phrase_pool.length, 5);
  assert.strictEqual(verifyData.categories[1].phrase_pool.length, 4);
  console.log(`✅ PASS: Saved template in Firestore with ${verifyData.categories.length} categories and 9 total phrases.`);

  // Cleanup
  await tRef.delete();
  console.log('\n🎉 ALL BULK PHRASE PARSING & DIVISION TESTS PASSED SUCCESSFULLY!');
}

runTest().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
