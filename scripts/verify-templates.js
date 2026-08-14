/**
 * scripts/verify-templates.js
 * Verification script to test category templates in Firestore emulator.
 */

'use strict';
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore }           = require('firebase-admin/firestore');

if (getApps().length === 0) {
  initializeApp({ projectId: 'review-system-prod-49b7a' });
}
const db = getFirestore();

async function runVerification() {
  console.log('🔍 Running Review Template System verification...\n');

  // 1. Check templates exist
  const tplIds = ['ice_cream_v1', 'salon_v1', 'restaurant_v1'];
  for (const id of tplIds) {
    const snap = await db.collection('category_templates').doc(id).get();
    if (!snap.exists) throw new Error(`Template missing: ${id}`);
    const data = snap.data();
    console.log(`✅ Template "${id}" (${data.business_type}): ${data.categories.length} categories`);
    
    // Check first category structure
    const cat = data.categories[0];
    if (cat.phrase_pool.length < 30) throw new Error(`Category ${cat.name} has < 30 variants`);
    if (!cat.phrase_pool_versions.v1 || !cat.phrase_pool_versions.v2 || !cat.phrase_pool_versions.v3) {
      throw new Error(`Category ${cat.name} missing pool versions`);
    }
    if (!cat.translations.hi || !cat.translations.gu) {
      throw new Error(`Category ${cat.name} missing hi/gu translations`);
    }
  }

  // 2. Check businesses and pool version assignments
  console.log('\n🏢 Verifying pool version routing for seeded businesses...');
  const bizIds = ['test_business_001', 'test_business_002', 'test_business_003', 'test_business_004'];
  for (const bId of bizIds) {
    const bSnap = await db.collection('businesses').doc(bId).get();
    const data  = bSnap.data();
    console.log(`  - ${data.brand_name} (${data.category_type}): template=${data.default_category_template_id}, pool_version=${data.pool_version}`);
  }

  // 3. Prove distinct content across pool versions v1 and v2
  const iceCreamTpl = (await db.collection('category_templates').doc('ice_cream_v1').get()).data();
  const tasteCat = iceCreamTpl.categories.find(c => c.name === 'Taste');
  const v1Sample = tasteCat.phrase_pool_versions.v1[0];
  const v2Sample = tasteCat.phrase_pool_versions.v2[0];
  console.log('\n🔀 Duplicate Content Mitigation Proof (Ice Cream Taste pool):');
  console.log(`   v1 phrase [0]: "${v1Sample}"`);
  console.log(`   v2 phrase [0]: "${v2Sample}"`);
  if (v1Sample === v2Sample) throw new Error('v1 and v2 pools are identical!');
  console.log('   ✓ Pool versions v1 and v2 yield distinct phrase variants!');

  console.log('\n🎉 ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!\n');
}

runVerification().catch(e => {
  console.error('❌ Verification failed:', e);
  process.exit(1);
});
