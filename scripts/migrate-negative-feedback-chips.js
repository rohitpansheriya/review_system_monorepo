/**
 * scripts/migrate-negative-feedback-chips.js
 * 
 * Backfills category-specific negative feedback chips for all currently enrolled
 * businesses in Firestore based on their selected business category / template.
 */

'use strict';
const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
if (getApps().length === 0) {
  const serviceAccountPath = path.join(__dirname, '..', 'serviceAccountKey.json');
  if (fs.existsSync(serviceAccountPath)) {
    const sa = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    initializeApp({
      credential: cert(sa),
      projectId: 'review-system-prod-49b7a'
    });
  } else {
    initializeApp({ projectId: 'review-system-prod-49b7a' });
  }
}
const db = getFirestore();

// 50 Category-Specific Negative Feedback Presets Dictionary
const NEGATIVE_PRESETS = {
  // Food & Dining (10)
  food_pizzeria: [
    '🍕 Soggy / burnt pizza crust',
    '🧀 Insufficient cheese / toppings',
    '🧊 Food served lukewarm / cold',
    '⏳ Long table waiting time',
    '👥 Inattentive table service',
    '💰 Overpriced for portion size'
  ],
  food_cafe: [
    '☕ Coffee too bitter / watery',
    '🧊 Incorrect beverage temperature',
    '🥐 Pastry / bakery item was stale',
    '📶 Wi-Fi slow / AC not working',
    '⏳ Long counter preparation delay',
    '👥 Barista rude / inattentive'
  ],
  food_bakery: [
    '🎂 Cake design mismatch',
    '🍰 Cake sponge dry or too sweet',
    '⏱️ Late delivery / missed pickup',
    '📦 Damaged packaging during transit',
    '💰 Custom design charges too high',
    '👥 Unhelpful counter staff'
  ],
  food_fast_food: [
    '🍔 Cold burger or soggy bun',
    '🍟 Fries limp / oversalted / cold',
    '📦 Missing item or wrong sauce',
    '⏳ Very slow counter ordering',
    '🧹 Dirty dining tables or floor',
    '👥 Unpleasant cashier behavior'
  ],
  food_north_indian: [
    '🍲 Gravy too oily / overly spicy',
    '🫓 Naan / Roti stiff or chewy',
    '🍗 Meat / paneer pieces tough',
    '⏳ Food took very long to arrive',
    '👥 Captain / staff unaccommodating',
    '💰 High taxes / unexpected service fee'
  ],
  food_south_indian: [
    '🥞 Dosa soggy or undercooked',
    '🥥 Sambar / Chutney watery or sour',
    '🧊 Filter coffee not piping hot',
    '⏳ Table clearing very slow',
    '🧹 Dining tables not wiped properly',
    '👥 Staff rushed and inattentive'
  ],
  food_chinese_asian: [
    '🍜 Noodles / rice overly greasy',
    '🧂 Excess Ajinomoto / high salt',
    '🥟 Dim sums dry or broken casing',
    '⏳ Main course delayed after starters',
    '👥 Waiter confused item numbers',
    '💰 Small portion for pricing'
  ],
  food_biryani: [
    '🍚 Biryani too dry / lacking spice',
    '🍗 Chicken / Mutton tough or smelly',
    '🧅 Salan / Raita sour or missing',
    '⏳ Order delayed during peak rush',
    '📦 Parcel spilled / poor container',
    '👥 Inefficient counter billing'
  ],
  food_ice_cream: [
    '🍨 Ice cream melted / icy texture',
    '🧇 Waffle cone soggy or cracked',
    '🍓 Desired flavors were out of stock',
    '⏳ Slow scooping & long queue',
    '🧹 Sticky counter or messy floor',
    '💰 Expensive per single scoop'
  ],
  food_fine_dining: [
    '🍷 Order mixup / courses poorly timed',
    '🥩 Food seasoning underwhelming',
    '⏳ Reserved table was not ready',
    '👥 Staff lacked basic etiquette',
    '🔊 Background music excessively loud',
    '💰 Exorbitant bill without quality'
  ],

  // Salons & Spas (10)
  salon_premium: [
    '💇 Haircut did not match reference',
    '🎨 Hair color patchy / wrong tone',
    '⏳ Waited 30+ mins despite appointment',
    '💰 Pushy upselling of products',
    '👥 Stylist rough or dismissive',
    '🧹 Hair cuttings left around chair'
  ],
  salon_barbershop: [
    '✂️ Uneven fade / uneven beard trim',
    '🪒 Razor burn / cut from trimming',
    '⏳ Excessive wait without queue system',
    '🧹 Unsanitized clipper / dirty cape',
    '👥 Barber rushed through service',
    '💰 Charged higher than rate chart'
  ],
  salon_nail_studio: [
    '💅 Gel extension chipped / lifted early',
    '🎨 Nail art messy or inaccurate',
    '⏳ Procedure took over 2.5 hours',
    '💅 Cuticle cut / nail pain during filing',
    '👥 Nail tech lacked proper skills',
    '💰 Hidden add-on removal charges'
  ],
  salon_skin_aesthetic: [
    '🧖 Skin irritation / breakout post-facial',
    '✨ No visible glow or results',
    '⏳ Doctor / esthetician arrived late',
    '💰 High consultation or product markup',
    '👥 Therapist pushed unwanted packages',
    '🧹 Treatment room smelled musty'
  ],
  salon_luxury_spa: [
    '💆 Massage therapist applied wrong pressure',
    '🔊 Room noisy / staff talking loudly outside',
    '⏱️ Therapist cut massage time short',
    '❄️ Massage room AC temperature too cold',
    '🧹 Towels / shower area felt damp or unclean',
    '💰 Spa package overpriced for experience'
  ],
  salon_makeup_bridal: [
    '💄 Foundation look cakey / mismatched shade',
    '👰 Makeup artist was significantly late',
    '👁️ Eyelashes / hair styling came loose',
    '💄 Unhygienic makeup brushes used',
    '👥 MUA was inflexible / dismissive',
    '💰 Sudden last-minute overtime fees'
  ],
  salon_tattoo_piercing: [
    '🎨 Tattoo linework shaky / uneven ink',
    '🩹 Poor aftercare instructions provided',
    '💉 Piercing placement crooked or infected',
    '🧹 Studio hygiene appeared questionable',
    '⏳ Artist kept customer waiting',
    '💰 High hourly rate for simple design'
  ],
  salon_lash_eyebrow: [
    '👁️ Lash extensions clumped or fell out early',
    '🤨 Eyebrow shape uneven / over-threaded',
    '👁️ Eye stinging / adhesive burning sensation',
    '⏳ Long waiting despite fixed slot',
    '👥 Technician seemed inexperienced',
    '💰 Infill sessions priced too high'
  ],
  salon_mens_grooming: [
    '🧔 Beard trim asymmetrical / cut too short',
    '💇 Haircut looked unblended',
    '⏳ Walk-in wait time exceeded 45 mins',
    '🧹 Towel smelled damp / tools not disinfected',
    '👥 Staff distracted on mobile phone',
    '💰 Expensive for standard quick cut'
  ],
  salon_foot_reflexology: [
    '🦶 Foot massage caused painful soreness',
    '⏱️ Session ended 10 mins early',
    '🔊 Loud chatter near massage chairs',
    '🛋️ Recliner chair uncomfortable',
    '👥 Masseuse lacked training',
    '💰 Not worth the fee charged'
  ],

  // Healthcare & Clinics (10)
  clinic_dental: [
    '🦷 Extreme pain during or after procedure',
    '⏱️ Cap / filling came loose quickly',
    '⏳ Waited 45+ mins past appointment time',
    '💰 Sudden hidden charges on dental bill',
    '👥 Dentist seemed rushed and impatient',
    '🧹 Operatory equipment looked dated'
  ],
  clinic_dermatology: [
    '🧴 Prescribed medicines caused severe reaction',
    '⏳ Consultation lasted less than 3 minutes',
    '💊 Very expensive branded lotions prescribed',
    '⏳ Clinic reception delayed queue by an hour',
    '👥 Doctor was dismissive of concerns',
    '💰 Repeated follow-up fees charged'
  ],
  clinic_pediatric: [
    '👶 Doctor lacked warmth / scared the child',
    '💉 Painful injection / rough handling',
    '⏳ Sick child had to wait over an hour',
    '🧹 Waiting room toys dirty or unhygienic',
    '👥 Receptionist was rude and unhelpful',
    '💰 Over-prescription of strong medicines'
  ],
  clinic_physiotherapy: [
    '🦴 Pain worsened following the session',
    '⏱️ Therapist left patient unattended on machines',
    '⏳ Long waiting time in reception',
    '👥 Therapist seemed disinterested',
    '🏢 Poorly maintained rehab equipment',
    '💰 Package fee demanded in advance'
  ],
  clinic_ent_audiology: [
    '👂 Ear cleaning procedure caused pain',
    '🔬 Inaccurate hearing test / misdiagnosis',
    '⏳ Delay in doctor arrival at clinic',
    '👥 Doctor did not explain the condition',
    '💰 Unnecessary tests or device suggested',
    '🧹 Noisy and crowded waiting area'
  ],
  clinic_eye_ophthalmology: [
    '👁️ Eye power prescription was incorrect',
    '⏳ Excessive waiting for eye drop dilation',
    '🔬 Doctor rushed the eye examination',
    '💰 High spectacle frame markup',
    '👥 Clinic staff lacked courteous behavior',
    '🧹 Dirty diagnostic chin rests'
  ],
  clinic_pathology_lab: [
    '💉 Painful vein puncture / bruising after blood test',
    '📋 Test report significantly delayed',
    '📄 Mixup in sample names or report values',
    '⏳ Long queue for routine blood collection',
    '👥 Phlebotomist did not sanitize hands',
    '💰 Price higher than other accredited labs'
  ],
  clinic_veterinary_pet: [
    '🐾 Pet handled roughly or with impatience',
    '🐕 Diagnosis was inaccurate / symptoms missed',
    '⏳ Long wait with distressed pets in lobby',
    '💰 Inflated medicine and consultation bill',
    '👥 Vet doctor lacked bedside empathy',
    '🧹 Pet examination table was uncleaned'
  ],
  clinic_orthopedic_spine: [
    '🦴 Doctor recommended immediate surgery without details',
    '⏳ Waited over 1.5 hours in waiting hall',
    '👥 Rushed 2-minute doctor consultation',
    '💰 Costly X-ray & MRI pushed at specific center',
    '🦴 Ineffective pain relief prescribed',
    '🏢 Inaccessible clinic for mobility-impaired'
  ],
  clinic_homeopathy_ayurveda: [
    '🌿 Medicines showed zero relief after months',
    '⏳ Doctor took consultation casually',
    '💰 Highly expensive monthly herbal kit',
    '⏱️ Delayed dispatch of courier medicines',
    '👥 Receptionist never answers calls',
    '🌿 Strict diet restrictions not explained'
  ],

  // Automotive (10)
  auto_car_service: [
    '🚗 Car issue was not resolved after service',
    '💰 Final bill exceeded initial estimate',
    '⏱️ Vehicle delivery delayed by days',
    '🛢️ Suspected non-genuine parts used',
    '👥 Service advisor was uncommunicative',
    '🧼 Car returned dirty or unwashed'
  ],
  auto_detailing_ppf: [
    '✨ PPF edges peeling / bubbles under film',
    '🚗 Swirl marks visible after ceramic coat',
    '⏳ Detailing job took 2 days longer than promised',
    '💰 Charged high premium for subpar finish',
    '👥 Workshop manager refused warranty rework',
    '🧼 Interior dust and stains left behind'
  ],
  auto_car_wash: [
    '🧼 Dirt and water stains left on vehicle body',
    '🧽 Scratches caused by dirty wash mitts',
    '⏳ 45-minute wait for a basic 10-minute wash',
    '🧹 Interior vacuuming was incomplete',
    '👥 Wash boy was careless with floor mats',
    '💰 Overcharged for basic foam shampoo'
  ],
  auto_tyre_wheel: [
    '🛞 Wheel alignment still pulling to one side',
    '🔩 Wheel nuts over-tightened / damaged studs',
    '⏳ Long wait time for tyre mounting',
    '💰 High tyre fitting or balancing surcharge',
    '👥 Staff pushed older stock tyres',
    '💨 Tyre pressure sensor damaged'
  ],
  auto_two_wheeler: [
    '🏍️ Engine knocking / mileage dropped post-service',
    '🔧 Brakes feel spongy or unsafe',
    '⏱️ Bike delivered late in the evening',
    '💰 Extra parts replaced without consent',
    '👥 Mechanic was untrained or careless',
    '🧼 Bike not properly washed or polished'
  ],
  auto_denting_painting: [
    '🎨 Mismatched paint shade / clearcoat peel',
    '🔨 Dent still slightly visible in daylight',
    '⏳ Delivery delayed by over a week',
    '💰 Paint estimate increased halfway through',
    '👥 Body shop supervisor made false promises',
    '🧼 Paint overspray on glass and rubber beadings'
  ],
  auto_car_audio: [
    '🔊 Loose dashboard panels / rattling sound',
    '⚡ Electrical fuse blown / wiring left exposed',
    '📻 Touchscreen Android system freezing',
    '💰 Heavy markup on cheap speaker brands',
    '👥 Installer lacked technical wiring knowledge',
    '⏳ Installation took entire day'
  ],
  auto_car_ac: [
    '❄️ AC cooling still weak / gas leaked within weeks',
    '💨 Bad smell coming from AC blower',
    '💰 Expensive compressor replacement insisted',
    '⏳ Long repair time without clear explanation',
    '👥 Technician lacked proper diagnostic tools',
    '🔩 AC cabin filter not replaced'
  ],
  auto_ev_charging: [
    '⚡ Charger gun not working / error code displayed',
    '📱 Mobile app failed to initiate session',
    '⏳ Charging speed way below advertised kW',
    '🅿️ ICE vehicles blocked charging bay',
    '💰 High idle or convenience fee billed',
    '👥 No customer helpline support available'
  ],
  auto_towing_crane: [
    '🚛 Towing vehicle arrived 2 hours late',
    '💥 Bumper or underbody scratched during loading',
    '💰 Demanded cash excess over agreed quote',
    '👥 Tow truck driver was rude and reckless',
    '📱 Location tracking did not update',
    '🛡️ No safety straps used during transport'
  ],

  // Retail & Shopping (10)
  retail_clothing: [
    '👗 Fabric tore / color bled on first wash',
    '🏷️ Refusal of size exchange / rigid return policy',
    '⏳ Long trial room and checkout queues',
    '💰 Overpriced tags compared to quality',
    '👥 Store staff was indifferent and unhelpful',
    '🧹 Messy clothing racks and untidy trial rooms'
  ],
  retail_footwear: [
    '👟 Shoe sole separated within few weeks',
    '👠 Desired shoe size was out of stock',
    '💰 High price for artificial leather / synthetic',
    '👥 Sales assistant rushed shoe trials',
    '🏷️ Warranty / return refused on defective pair',
    '📦 Given shop-soiled display shoe'
  ],
  retail_electronics: [
    '📱 Defective device given / sealed box tampered',
    '🏷️ Staff gave wrong technical specs advice',
    '⏳ Billing and warranty entry took 45 mins',
    '💰 Accessory prices marked up significantly',
    '👥 Salesperson was unhelpful after payment',
    '🛡️ Extended warranty terms misleading'
  ],
  retail_jewelry: [
    '💎 Making charges / wastage fee unexpectedly high',
    '💍 Sizing alteration was delayed and loose',
    '📜 Lack of clear hallmark or purity certification',
    '👥 Staff showed attitude for smaller purchases',
    '💰 Resale / buyback deductions were steep',
    '📦 Inadequate jewelry presentation box'
  ],
  retail_eyewear: [
    '👓 Lens power incorrect / causing headaches',
    '🕶️ Frame hinge became loose in days',
    '⏱️ Specs delivery took over 10 days',
    '💰 Anti-glare coating started peeling',
    '👥 Optometrist conducted very hasty eye test',
    '🏷️ High frame pricing without discount'
  ],
  retail_home_decor: [
    '🛋️ Furniture delivered with scratches or dents',
    '🪵 Wood quality felt cheap compared to showroom',
    '⏱️ Home delivery delayed by 3 weeks',
    '💰 High delivery and installation surcharge',
    '👥 Assembly carpenter was unskilled',
    '📦 Incomplete parts sent in shipment'
  ],
  retail_supermarket: [
    '🛒 Expired or near-expiry groceries on shelves',
    '⏳ Only 1 billing counter open with huge queue',
    '💰 Shelf price differed from scanner bill price',
    '🥬 Wilted vegetables and soft fruits',
    '👥 Cashier was slow and made scanning errors',
    '📦 Poor quality carry bags that tear easily'
  ],
  retail_gift_novelties: [
    '🎁 Personalized printing was crooked or blurry',
    '⏱️ Gift item was not ready for event date',
    '💰 Overcharged for simple decorative gift wrap',
    '📦 Fragile item packed carelessly without bubble wrap',
    '👥 Shopkeeper was impatient during selection',
    '🏷️ Defective souvenir item cannot be exchanged'
  ],
  retail_books_stationery: [
    '📚 Textbook / novel edition out of stock',
    '✏️ Pens or stationery dried up / defective',
    '💰 Charged higher than printed MRP',
    '👥 Counter staff lacked knowledge of book titles',
    '⏳ Very slow photocopy / printout counter',
    '🧹 Cramped and dusty bookshelves'
  ],
  retail_sports_fitness: [
    '🏸 Equipment broke or bent during first use',
    '👟 Sports shoes had poor grip and padding',
    '💰 Gym accessories priced excessively high',
    '👥 Staff gave inaccurate advice on equipment size',
    '🏷️ No replacement policy on fitness gear',
    '📦 Delivered gym weight set was missing clips'
  ],

  universal_general: [
    '⏳ Long waiting time or delay in delivery',
    '💰 High billing or unexpected extra charges',
    '👥 Unprofessional or discourteous staff behavior',
    '🧹 Cleanliness and hygiene concerns',
    '👎 Service quality did not meet expectations',
    '📦 Incomplete work or missing items'
  ],
  it_software_agency: [
    '⏳ Unexplained project delay / missed milestone',
    '🐛 Unstable deployment / bugs in production',
    '📞 Poor communication / lack of status updates',
    '💰 Unexpected billing / scope creep fees',
    '🎨 Design did not meet agreed specifications',
    '🛠️ Slow resolution on critical support tickets'
  ],
  it_computer_hardware_repair: [
    '⏳ Unreasonable repair turnaround delay',
    '⚠️ Recurring hardware fault / issue persists',
    '💰 Final invoice exceeded initial estimate',
    '💾 Data loss during servicing',
    '👥 Impolite technician / poor communication',
    '🔩 Substandard replacement parts used'
  ],
  it_cloud_devops_consulting: [
    '⚠️ System downtime during migration',
    '💰 Unanticipated cloud cost spikes',
    '⏳ Slow response on urgent server alerts',
    '📋 Incomplete documentation / handoff',
    '🐛 Pipeline failure / broken release build',
    '📞 Inadequate communication during outage'
  ]
};

function resolveNegativeChips(catType, templateId, archetype) {
  if (templateId && NEGATIVE_PRESETS[templateId]) {
    return NEGATIVE_PRESETS[templateId];
  }

  const query = `${catType || ''} ${templateId || ''}`.toLowerCase();
  for (const key in NEGATIVE_PRESETS) {
    const shortKey = key.replace(/^(food|salon|clinic|auto|retail|it)_/, '');
    if (query.includes(shortKey) || shortKey.includes(query)) {
      return NEGATIVE_PRESETS[key];
    }
  }

  const archKey = {
    'food_dining': 'food_pizzeria',
    'beauty_wellness': 'salon_premium',
    'healthcare_clinic': 'clinic_dental',
    'auto_services': 'auto_car_service',
    'retail_shopping': 'retail_clothing',
    'it_services': 'it_software_agency',
    'universal_general': 'universal_general'
  }[archetype] || 'universal_general';

  return NEGATIVE_PRESETS[archKey] || NEGATIVE_PRESETS.universal_general;
}

async function migrate() {
  console.log('🚀 Starting Negative Feedback Chips migration for existing businesses...\n');
  const snap = await db.collection('businesses').get();
  console.log(`Found ${snap.size} businesses in Firestore.`);

  let updatedCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const id = doc.id;
    const name = data.brand_name || 'Unnamed';
    const catType = data.category_type || '';
    const templateId = data.default_category_template_id || '';
    const archetype = data.archetype || 'food_dining';

    const targetChips = resolveNegativeChips(catType, templateId, archetype);

    await db.collection('businesses').doc(id).update({
      negative_feedback_chips: targetChips
    });
    console.log(`✅ [${id}] "${name}" (${catType || templateId || archetype}) -> Assigned ${targetChips.length} negative chips.`);
    updatedCount++;
  }

  console.log(`\n🎉 Migration complete! Updated ${updatedCount} businesses.\n`);
}

migrate().catch(err => {
  console.error('❌ Migration failed:', err);
  process.exit(1);
});
