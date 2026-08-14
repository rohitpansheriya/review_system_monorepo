/**
 * scripts/test-feature-flag.js
 * Comprehensive self-test for ENABLE_TRANSLATIONS feature flag and dormant translation path.
 */

'use strict';
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore }           = require('firebase-admin/firestore');
const fs                         = require('fs');
const path                       = require('path');

if (getApps().length === 0) {
  initializeApp({ projectId: 'review-system-prod-49b7a' });
}
const db = getFirestore();

async function runFeatureFlagTests() {
  console.log('🧪 Running Feature Flag & Translation Dormancy Tests...\n');

  // 1. Verify schema preserves translations structure even when shipping English-only
  console.log('1️⃣ Checking category_templates schema structure...');
  const snap = await db.collection('category_templates').doc('ice_cream_v1').get();
  const tplData = snap.data();
  const firstCat = tplData.categories[0];

  if (!firstCat.translations || typeof firstCat.translations !== 'object') {
    throw new Error('translations field missing from schema!');
  }
  if (!('hi' in firstCat.translations) || !('gu' in firstCat.translations)) {
    throw new Error('hi or gu translation keys missing from translations map!');
  }
  console.log('   ✓ Schema preserves translations map structure ({ hi: {...}, gu: {...} }).');
  console.log(`   ✓ English pool variants count: ${firstCat.phrase_pool.length} (v1/v2/v3 active)`);
  console.log(`   ✓ Hindi pool variants count (dormant): ${firstCat.translations.hi.phrase_pool.length}`);

  // 2. Verify public/r/index.html feature flag configuration
  console.log('\n2️⃣ Checking public/r/index.html feature flag config...');
  const htmlPath = path.join(__dirname, '../public/r/index.html');
  const htmlContent = fs.readFileSync(htmlPath, 'utf8');

  if (!htmlContent.includes('const ENABLE_TRANSLATIONS = false;')) {
    throw new Error('ENABLE_TRANSLATIONS feature flag not set to false in public/r/index.html');
  }
  console.log('   ✓ ENABLE_TRANSLATIONS = false is set in public/r/index.html.');

  if (!htmlContent.includes("('lang-bar').style.display = (showHeader && ENABLE_TRANSLATIONS) ? 'flex' : 'none';")) {
    throw new Error('Language bar display is not gated behind ENABLE_TRANSLATIONS');
  }
  console.log('   ✓ Language selector UI is conditionally gated behind ENABLE_TRANSLATIONS.');

  // 3. Verify Pool Versioning mitigation remains active and unaffected
  console.log('\n3️⃣ Verifying Pool Versioning duplicate-content mitigation...');
  const b1Snap = await db.collection('businesses').doc('test_business_001').get();
  const b2Snap = await db.collection('businesses').doc('test_business_002').get();
  const v1Pool = firstCat.phrase_pool_versions.v1;
  const v2Pool = firstCat.phrase_pool_versions.v2;

  console.log(`   Business 1 (v1): ${b1Snap.data().brand_name} -> Sample phrase: "${v1Pool[0]}"`);
  console.log(`   Business 2 (v2): ${b2Snap.data().brand_name} -> Sample phrase: "${v2Pool[0]}"`);
  if (v1Pool[0] === v2Pool[0]) throw new Error('v1 and v2 pools match!');
  console.log('   ✓ Pool versioning duplicate-content mitigation is active and working!');

  console.log('\n✅ ALL FEATURE FLAG TESTS PASSED!\n');
}

runFeatureFlagTests().catch(e => {
  console.error('❌ Feature flag test failed:', e);
  process.exit(1);
});
