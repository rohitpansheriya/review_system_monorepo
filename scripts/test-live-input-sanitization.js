/**
 * test-live-input-sanitization.js
 *
 * Verifies live input sanitization logic:
 * 1. Place ID whitespace stripping (leading/trailing/internal/newlines) -> clean Google review link (no %20).
 * 2. URL-safe format validation for Place ID ([a-zA-Z0-9_-]) with inline warning detection.
 * 3. No corrupting character substitutions (e.g. pipe is flagged by warning, not silently mutated).
 * 4. Phone number stripping (spaces, dashes, brackets, +91/0 prefix) -> standard clean E.164 & wa.me format.
 * 5. Text whitespace collapsing (multiple consecutive spaces -> single space, trimmed).
 * 6. Email sanitization (trimmed, lowercased).
 * 7. Multi-branch verification: branch 1, 2, and 3 all get independently sanitized.
 */

const assert = require('assert');

// ── 1. Place ID Sanitization & Review Link Generator ────────────────────────
function sanitizePlaceId(input) {
  if (!input) return '';
  return input.trim().replace(/\s+/g, '');
}

function isValidPlaceIdFormat(input) {
  if (!input || !input.trim()) return false;
  const clean = sanitizePlaceId(input);
  return /^[a-zA-Z0-9_-]+$/.test(clean);
}

function buildGoogleReviewLink(placeId) {
  const clean = sanitizePlaceId(placeId);
  return clean ? `https://search.google.com/local/writereview?placeid=${clean}` : null;
}

// ── 2. Phone Sanitization ───────────────────────────────────────────────────
function cleanPhoneDigits(raw) {
  if (!raw) return '';
  let digits = raw.replace(/\D/g, '');
  if (digits.startsWith('91') && digits.length > 10) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0') && digits.length > 10) {
    digits = digits.substring(1);
  }
  if (digits.length > 10) {
    digits = digits.substring(0, 10);
  }
  return digits;
}

function toE164(raw) {
  const digits = cleanPhoneDigits(raw);
  return digits ? `+91${digits}` : '';
}

function toWaMeLink(e164Phone, message = '') {
  // Strip leading '+' as done in public/r/index.html
  const cleanNumber = (e164Phone || '').replace(/^\+/, '').replace(/\D/g, '');
  return `https://wa.me/${cleanNumber}${message ? `?text=${encodeURIComponent(message)}` : ''}`;
}

// ── 3. General Text & Email Normalization ───────────────────────────────────
function collapseWhitespace(input) {
  if (!input) return '';
  return input.trim().replace(/\s+/g, ' ');
}

function sanitizeEmail(input) {
  if (!input) return '';
  return input.trim().toLowerCase();
}

// ── Test Execution ──────────────────────────────────────────────────────────
async function runTests() {
  console.log('🧪 Running Live Input Sanitization Test Suite...\n');

  // Test 1: Place ID with leading/trailing/internal whitespace
  console.log('--- TEST 1: Place ID Sanitization & Review Link ---');
  const dirtyPlaceId = '  ChIJN1t_tDeuEmsRUsoyG83frY4  ';
  const cleanPlaceId = sanitizePlaceId(dirtyPlaceId);
  assert.strictEqual(cleanPlaceId, 'ChIJN1t_tDeuEmsRUsoyG83frY4');
  assert.strictEqual(isValidPlaceIdFormat(cleanPlaceId), true);
  
  const reviewLink = buildGoogleReviewLink(dirtyPlaceId);
  assert.strictEqual(reviewLink, 'https://search.google.com/local/writereview?placeid=ChIJN1t_tDeuEmsRUsoyG83frY4');
  assert.strictEqual(reviewLink.includes('%20'), false, 'Review link must not contain %20 whitespace');
  console.log('✅ PASS: Dirty Place ID "  ChIJ...  " cleaned to "ChIJ..." with clean review link.');

  // Test 2: Place ID with internal newline / spaces
  const internalSpacePlaceId = 'ChIJN1t_t\nDeuEms RUsoyG83frY4';
  const cleanInternal = sanitizePlaceId(internalSpacePlaceId);
  assert.strictEqual(cleanInternal, 'ChIJN1t_tDeuEmsRUsoyG83frY4');
  console.log('✅ PASS: Internal spaces/newlines stripped without character corruption.');

  // Test 3: Bad Place ID Format Detection (Inline warning, non-blocking)
  console.log('\n--- TEST 2: Place ID Invalid Character Warning ---');
  const badPlaceId = 'ChIJ|invalid_char!';
  assert.strictEqual(isValidPlaceIdFormat(badPlaceId), false, 'Place ID with pipe/exclamation should flag invalid format');
  assert.strictEqual(isValidPlaceIdFormat('ChIJ-Valid_123'), true, 'Alphanumeric with hyphens/underscores is valid');
  console.log('✅ PASS: Invalid characters (pipes, symbols) correctly detected for inline warning.');

  // Test 4: Phone / WhatsApp Sanitization
  console.log('\n--- TEST 3: Phone / WhatsApp Sanitization & wa.me Links ---');
  const testPhones = [
    { input: '+91 98765-43210', expectedDigits: '9876543210', expectedE164: '+919876543210', expectedWaMe: 'https://wa.me/919876543210' },
    { input: '09876543210', expectedDigits: '9876543210', expectedE164: '+919876543210', expectedWaMe: 'https://wa.me/919876543210' },
    { input: '(987) 654 3210', expectedDigits: '9876543210', expectedE164: '+919876543210', expectedWaMe: 'https://wa.me/919876543210' },
    { input: '  9876543210  ', expectedDigits: '9876543210', expectedE164: '+919876543210', expectedWaMe: 'https://wa.me/919876543210' },
  ];

  for (const t of testPhones) {
    const digits = cleanPhoneDigits(t.input);
    const e164 = toE164(t.input);
    const wame = toWaMeLink(e164);
    assert.strictEqual(digits, t.expectedDigits);
    assert.strictEqual(e164, t.expectedE164);
    assert.strictEqual(wame, t.expectedWaMe);
  }
  console.log('✅ PASS: All phone formats (+91, 0-prefix, dashes, spaces, brackets) normalized to 10-digit clean E.164 and valid wa.me URLs.');

  // Test 5: Business Name / Owner Name / Address Whitespace Collapsing
  console.log('\n--- TEST 4: Text Whitespace Collapsing & Normalization ---');
  const rawBusinessName = '   Shree   Ram    Sweets   &   Cafe   ';
  const cleanBusinessName = collapseWhitespace(rawBusinessName);
  assert.strictEqual(cleanBusinessName, 'Shree Ram Sweets & Cafe');

  const rawAddress = '  Shop 4,   Main Market,  \n  Andheri West,   Mumbai 400058  ';
  const cleanAddress = collapseWhitespace(rawAddress);
  assert.strictEqual(cleanAddress, 'Shop 4, Main Market, Andheri West, Mumbai 400058');
  console.log('✅ PASS: Multiple consecutive spaces & newlines collapsed to single space.');

  // Test 6: Email Normalization
  console.log('\n--- TEST 5: Email Normalization ---');
  const rawEmail = '   Owner.Contact@EXAMPLE.Com   ';
  const cleanEmail = sanitizeEmail(rawEmail);
  assert.strictEqual(cleanEmail, 'owner.contact@example.com');
  console.log('✅ PASS: Email trimmed and lowercased.');

  // Test 7: Multi-Branch Independence
  console.log('\n--- TEST 6: Multi-Branch Independent Sanitization ---');
  const branchDrafts = [
    { name: '  Branch   1  ', placeId: '  ChIJ_Branch_1  ', phone: '98765-11111' },
    { name: '  Branch   2  ', placeId: '  ChIJ_Branch_2  ', phone: '+91 98765 22222' },
    { name: '  Branch   3  ', placeId: '  ChIJ_Branch_3  ', phone: '09876533333' },
  ];

  const cleanedBranches = branchDrafts.map((b) => ({
    name: collapseWhitespace(b.name),
    placeId: sanitizePlaceId(b.placeId),
    phone: toE164(b.phone),
    reviewLink: buildGoogleReviewLink(b.placeId),
  }));

  assert.strictEqual(cleanedBranches[0].name, 'Branch 1');
  assert.strictEqual(cleanedBranches[0].placeId, 'ChIJ_Branch_1');
  assert.strictEqual(cleanedBranches[0].phone, '+919876511111');
  assert.strictEqual(cleanedBranches[0].reviewLink, 'https://search.google.com/local/writereview?placeid=ChIJ_Branch_1');

  assert.strictEqual(cleanedBranches[1].name, 'Branch 2');
  assert.strictEqual(cleanedBranches[1].placeId, 'ChIJ_Branch_2');
  assert.strictEqual(cleanedBranches[1].phone, '+919876522222');
  assert.strictEqual(cleanedBranches[1].reviewLink, 'https://search.google.com/local/writereview?placeid=ChIJ_Branch_2');

  assert.strictEqual(cleanedBranches[2].name, 'Branch 3');
  assert.strictEqual(cleanedBranches[2].placeId, 'ChIJ_Branch_3');
  assert.strictEqual(cleanedBranches[2].phone, '+919876533333');
  assert.strictEqual(cleanedBranches[2].reviewLink, 'https://search.google.com/local/writereview?placeid=ChIJ_Branch_3');

  console.log('✅ PASS: Branches 1, 2, and 3 sanitized independently across all fields.');

  console.log('\n🎉 ALL LIVE INPUT SANITIZATION TESTS PASSED SUCCESSFULLY!');
}

runTests().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
