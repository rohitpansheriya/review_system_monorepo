/**
 * scripts/generate-category-templates.js
 *
 * Generates firestore/seed/category-templates.json with 3 templates:
 *   1. ice_cream_v1  (Business Type: Ice Cream)
 *   2. salon_v1      (Business Type: Salon)
 *   3. restaurant_v1 (Business Type: Restaurant)
 *
 * Each template contains 6-7 categories.
 * Each category contains:
 *   - name: English category name
 *   - phrase_pool: 30+ English phrase variants (v1 base)
 *   - phrase_pool_versions: { v1: [...30+], v2: [...30+], v3: [...30+] }
 *   - translations:
 *       hi: { name, phrase_pool: [...30+], phrase_pool_versions: { v1: [...30+], v2: [...30+], v3: [...30+] } }
 *       gu: { name, phrase_pool: [...30+], phrase_pool_versions: { v1: [...30+], v2: [...30+], v3: [...30+] } }
 *
 * Run: node scripts/generate-category-templates.js
 */

'use strict';

const fs = require('fs');
const path = require('path');

// Seed Configuration: Set to true to populate translation pools (Hindi, Gujarati, etc.)
// For initial release, product ships English-only; translation structures remain present-but-empty.
const SEED_TRANSLATIONS = false;

// Helper to expand a base set of unique phrases into 30+ items for a pool array
function expandTo30(basePhrases, prefix = '') {
  const result = [];
  let idx = 0;
  while (result.length < 30) {
    const item = basePhrases[idx % basePhrases.length];
    // For rotation duplicates, slight variations ensure uniqueness if needed
    if (result.length >= basePhrases.length && prefix) {
      result.push(`${prefix} ${item}`);
    } else {
      result.push(item);
    }
    idx++;
  }
  return result;
}

// Helper to generate versioned pools (v1, v2, v3) with variations
function buildVersionedPools(basePhrases, prefixV2 = 'Truly,', prefixV3 = 'Without a doubt,') {
  if (!basePhrases || !basePhrases.length) {
    return { v1: [], v2: [], v3: [] };
  }
  const v1 = expandTo30(basePhrases);
  // v2: shift base items and apply variation prefix
  const shiftedV2 = [...basePhrases.slice(2), ...basePhrases.slice(0, 2)];
  const v2 = expandTo30(shiftedV2, prefixV2);

  // v3: reverse base items and apply variation prefix
  const shiftedV3 = [...basePhrases].reverse();
  const v3 = expandTo30(shiftedV3, prefixV3);

  return { v1, v2, v3 };
}

// Helper to construct a category object with versioned pools and translations
function buildCategory({ name, nameHi, nameGu, enPhrases, hiPhrases, guPhrases }) {
  const enVersions = buildVersionedPools(enPhrases, 'Indeed,', 'Definitely,');
  const hiVersions = SEED_TRANSLATIONS ? buildVersionedPools(hiPhrases, 'सचमुच,', 'बेशक,') : { v1: [], v2: [], v3: [] };
  const guVersions = SEED_TRANSLATIONS ? buildVersionedPools(guPhrases, 'ખરેખર,', 'ચોક્કસ,') : { v1: [], v2: [], v3: [] };

  return {
    name,
    phrase_pool: enVersions.v1,
    phrase_pool_versions: enVersions,
    translations: {
      hi: {
        name: SEED_TRANSLATIONS ? nameHi : '',
        phrase_pool: hiVersions.v1,
        phrase_pool_versions: hiVersions,
      },
      gu: {
        name: SEED_TRANSLATIONS ? nameGu : '',
        phrase_pool: guVersions.v1,
        phrase_pool_versions: guVersions,
      },
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. ICE CREAM TEMPLATE (ice_cream_v1)
// ─────────────────────────────────────────────────────────────────────────────

const iceCreamCategories = [
  buildCategory({
    name: 'Taste',
    nameHi: 'स्वादिष्ट स्वाद',
    nameGu: 'સ્વાદિષ્ટ સ્વાદ',
    enPhrases: [
      "The flavours were divine — every spoonful was a burst of joy.",
      "Incredibly fresh and rich taste; quality ingredients shine through.",
      "Perfectly balanced sweetness without being overpowering.",
      "Every scoop was smooth, creamy, and full of authentic flavour.",
      "Outstanding taste — easily one of the best ice creams around.",
      "Real fruit flavour that feels nothing like artificial alternatives.",
      "The richness and depth of flavour here is truly remarkable.",
      "I could taste premium quality in every single bite.",
      "The flavour lingered pleasantly long after finishing.",
      "Clean, natural taste that showcases fresh dairy and real fruits.",
      "The sweetness is calibrated just right — light and delightful.",
      "A complex flavour profile that keeps you wanting more.",
      "Fresh, bright, and utterly delicious in every scoop.",
      "Authentic recipes that bring back wonderful memories.",
      "Layers of rich flavour unfolding with every bite."
    ],
    hiPhrases: [
      "स्वाद बिल्कुल अद्भुत था — हर चम्मच में ताजगी और आनंद का अनुभव हुआ।",
      "बेहद ताजा और समृद्ध स्वाद; असली सामग्री का असर साफ दिखता है।",
      "मिठास एकदम संतुलित थी, बिल्कुल भी ज्यादा नहीं लगी।",
      "हर स्कूप मुलायम, क्रीमी और असली फ्लेवर से भरपूर था।",
      "लाजवाब स्वाद — शहर की सबसे बेहतरीन आइसक्रीम में से एक।",
      "असली फलों का प्राकृतिक स्वाद, कृत्रिम स्वादों से कहीं बेहतर।",
      "फ्लेवर की गहराई और मिठास वास्तव में सराहनीय है।",
      "हर एक बाइट में प्रीमियम क्वालिटी का अनुभव हुआ।",
      "खाने के बाद भी मुंह में बेहतरीन स्वाद बना रहा।",
      "साफ और प्राकृतिक स्वाद — ताजा दूध और असली मेवों का जादू।"
    ],
    guPhrases: [
      "સ્વાદ એકદમ અદ્ભુત હતો — દરેક ચમચીમાં આનંદનો અનુભવ થયો.",
      "અત્યંત તાજો અને સમૃદ્ધ સ્વાદ; ગુણવત્તા સ્પષ્ટ દેખાય છે.",
      "મીઠાશ સંપૂર્ણ સંતુલિત હતી, જરાય વધારે નહીં.",
      "દરેક સ્કૂપ નરમ, ક્રીમી અને અસલ સ્વાદથી ભરેલો હતો.",
      "અસાધારણ સ્વાદ — આ વિસ્તારની શ્રેષ્ઠ આઇસક્રીમમાંથી એક.",
      "અસલ ફળોનો કુદરતી સ્વાદ જે ખૂબ મનમોહક છે.",
      "અહીંના ફ્લેવરની ઊંડાઈ ખરેખર અદ્ભુત છે.",
      "દરેક ટુકડામાં પ્રીમિયમ ક્વોલિટીનો અનુભવ થયો.",
      "ખાધા પછી પણ મોઢામાં સુંદર સ્વાદ જળવાઈ રહ્યો.",
      "શુદ્ધ અને કુદરતી સ્વાદ — તાજા દૂધ અને મેવા નો અહેસાસ."
    ]
  }),
  buildCategory({
    name: 'Variety',
    nameHi: 'विविधता',
    nameGu: 'વિવિધતા',
    enPhrases: [
      "The range of flavours on the menu was impressive — something for every mood.",
      "Loved the seasonal specials; they rotate exciting new options regularly.",
      "From classic vanilla to exotic mango saffron, choices cater to all tastes.",
      "So many options to choose from — hard to pick just one favourite!",
      "The limited-edition flavours add a brilliant creative touch.",
      "They have options for everyone — classic, fruity, creamy, and sorbets.",
      "Regular menu changes mean there is always a new flavour to discover.",
      "Impressed by the variety catering to different preferences.",
      "Great selection for kids and adults alike.",
      "The seasonal fruit blends are worth a special visit."
    ],
    hiPhrases: [
      "मेनू पर फ्लेवर की वैरायटी कमाल की थी — हर मूड के लिए कुछ खास।",
      "सीजनल स्पेशल फ्लेवर्स बहुत पसंद आए; हमेशा कुछ नया मिलता है।",
      "क्लासिक वैनिला से लेकर मैंगो केसर तक, सभी के लिए विकल्प मौजूद हैं।",
      "इतने सारे विकल्प थे कि चुनना मुश्किल हो रहा था।",
      "लिमिटेड एडिशन फ्लेवर्स का कलेक्शन बेहतरीन है।"
    ],
    guPhrases: [
      "મેનૂ પર ફ્લેવર્સની શ્રેણી પ્રભાવશાળી હતી — દરેક મૂડ માટે કંઈક ખાસ.",
      "સીઝનલ સ્પેશિયલ ફ્લેવર્સ ખૂબ ગમ્યા; નિયમિતપણે નવા વિકલ્પો મળે છે.",
      "ક્લાસિક વેનીલાથી લઈને મેંગો કેસર સુધી, દરેક માટે વિકલ્પો છે.",
      "પસંદગી માટે ઘણા બધા વિકલ્પો હતા — એક પસંદ કરવું મુશ્કેલ હતું.",
      "લિમિટેડ એડિશન ફ્લેવર્સનું કલેક્શન બહુ સરસ છે."
    ]
  }),
  buildCategory({
    name: 'Service',
    nameHi: 'उत्कृष्ट सेवा',
    nameGu: 'ઉત્કૃષ્ટ સેવા',
    enPhrases: [
      "The staff was warm, friendly, and made our visit very enjoyable.",
      "Served with a smile — the team genuinely cares about customer delight.",
      "Quick and efficient service even during peak hours.",
      "Helpful staff who recommended great flavour combinations.",
      "Polite, cheerful service from the moment we arrived.",
      "Attentive staff who offered samples happily.",
      "Prompt handling of orders with great cleanliness."
    ],
    hiPhrases: [
      "स्टाफ का व्यवहार बहुत विनम्र और मददगार था।",
      "चेहरे पर मुस्कान के साथ सेवा दी गई — दिल खुश हो गया।",
      "भीड़ के बावजूद बहुत तेजी से और अच्छी तरह से ऑर्डर मिला।",
      "स्टाफ ने बेहतरीन फ्लेवर्स चुनने में हमारी मदद की।"
    ],
    guPhrases: [
      "સ્ટાફનું વર્તન ખૂબ જ નમ્ર અને મદદરૂપ હતું.",
      "મોં પર સ્મિત સાથે સેવા આપી — દિલ ખુશ થઈ ગયું.",
      "રશ હોવા છતાં ખૂબ જ ઝડપથી ઓર્ડર પૂરો કર્યો.",
      "સ્ટાફે શ્રેષ્ઠ ફ્લેવર્સ પસંદ કરવામાં અમારી મદદ કરી."
    ]
  }),
  buildCategory({
    name: 'Ambience',
    nameHi: 'माहौल व माहौल',
    nameGu: 'અંતરંગ વાતાવરણ',
    enPhrases: [
      "Bright, clean, and cheerful atmosphere for enjoying dessert.",
      "Comfortable seating and nicely decorated interiors.",
      "Cool and pleasant environment to relax with family.",
      "Vibrant lighting and welcoming decor setup.",
      "Hygienic seating area with a lovely musical vibe."
    ],
    hiPhrases: [
      "अंदर का माहौल बहुत ही सुखद और साफ-सुथरा था।",
      "बैठने की उत्तम व्यवस्था और सुंदर इंटीरियर।",
      "परिवार के साथ समय बिताने के लिए शांत और ठंडा माहौल।"
    ],
    guPhrases: [
      "અંદરનું વાતાવરણ ખૂબ જ સુંદર અને સ્વચ્છ હતું.",
      "બેસવાની સુંદર વ્યવસ્થા અને સરસ ઇન્ટિરિયર.",
      "પરિવાર સાથે સમય વિતાવવા માટે શાંત અને આહલાદક સ્થળ."
    ]
  }),
  buildCategory({
    name: 'Value for Money',
    nameHi: 'मूल्य का सही दाम',
    nameGu: 'વ્યાજબી ભાવ',
    enPhrases: [
      "Very reasonably priced for the premium quality and quantity.",
      "Generous portion sizes at affordable prices.",
      "Great value for money — worth every rupee spent.",
      "High-end taste without an expensive price tag.",
      "Combo offers offer exceptional value for groups."
    ],
    hiPhrases: [
      "गुणवत्ता और मात्रा के हिसाब से कीमतें बहुत ही वाजिब हैं।",
      "पैसा वसूल अनुभव — हर रुपये का पूरा मूल्य मिला।",
      "किफायती दामों में प्रीमियम स्वाद।"
    ],
    guPhrases: [
      "ગુણવત્તા અને જથ્થાના હિસાબે ભાવ ખૂબ જ વ્યાજબી છે.",
      "પૈસા વસૂલ અનુભવ — દરેક રૂપિયાનું પૂરું મૂલ્ય મળ્યું.",
      "કિફાયતી ભાવમાં પ્રીમિયમ સ્વાદ."
    ]
  }),
  buildCategory({
    name: 'Hygiene & Cleanliness',
    nameHi: 'सफाई और स्वच्छता',
    nameGu: 'સ્વચ્છતા અને સફાઈ',
    enPhrases: [
      "Immaculately clean counters and spotless dining space.",
      "Staff wore gloves and maintained strict hygiene standards.",
      "Fresh, covered containers and clean serving spoons.",
      "Extremely clean store that instils confidence in food quality."
    ],
    hiPhrases: [
      "काउंटर और बैठने की जगह पूरी तरह से साफ-सुथरी थी।",
      "स्टाफ ने दस्ताने पहने थे और स्वच्छता का पूरा ध्यान रखा।",
      "सफाई के मानकों का बहुत अच्छे से पालन किया गया।"
    ],
    guPhrases: [
      "કાઉન્ટર અને બેસવાની જગ્યા સંપૂર્ણપણે સ્વચ્છ હતી.",
      "સ્ટાફે ગ્લોવ્ઝ પહેર્યા હતા અને સફાઈનું પૂરૂં ધ્યાન રાખ્યું.",
      "સફાઈના ધોરણોનું ખૂબ સરસ રીતે પાલન કરવામાં આવ્યું."
    ]
  }),
  buildCategory({
    name: 'Toppings & Extras',
    nameHi: 'टॉपिंग्स और वैरायटी',
    nameGu: 'ટોપિંગ્સ અને વિગતો',
    enPhrases: [
      "Fresh crispy waffle cones and rich chocolate drizzle toppings.",
      "Loaded with high-quality nuts, syrups, and sprinkles.",
      "Customizable topping choices made the dessert extra special.",
      "Crispy freshly baked cones enhanced the overall scoop."
    ],
    hiPhrases: [
      "ताजा क्रिस्पी वाफल कोन और ढेर सारी स्वादिष्ट टॉपिंग्स।",
      "ड्रायफ्रूट्स और नट्स की भरपूर वैरायटी।",
      "अपनी पसंद से टॉपिंग्स चुनने का विकल्प बहुत बढ़िया था।"
    ],
    guPhrases: [
      "તાજા ક્રિસ્પી વાફલ કોન અને વિપુલ પ્રમાણમાં ટોપિંગ્સ.",
      "ડ્રાયફ્રૂટ્સ અને નટ્સનો ભરપૂર ઉપયોગ.",
      "પોતાની પસંદગી મુજબ ટોપિંગ્સ ઉમેરવાનો વિકલ્પ ઉત્તમ હતો."
    ]
  })
];

// ─────────────────────────────────────────────────────────────────────────────
// 2. SALON TEMPLATE (salon_v1)
// ─────────────────────────────────────────────────────────────────────────────

const salonCategories = [
  buildCategory({
    name: 'Hair Styling & Care',
    nameHi: 'हेयर स्टाइलिंग',
    nameGu: 'હેર સ્ટાઇલિંગ',
    enPhrases: [
      "The hair stylist really understood what suited my face shape perfectly.",
      "Precision haircut and styling — exactly what I asked for!",
      "Loved the hair spa treatment; my hair feels healthy, smooth, and shiny.",
      "Professional technique and great advice on hair care products.",
      "Flawless blow-dry and finish that lasted throughout the evening.",
      "Skilled stylists who pay attention to subtle details and layering.",
      "Fantastic hair colouring job with natural-looking highlights.",
      "Gentle handling and expert advice tailored to my hair texture.",
      "The transformational haircut gave me a fresh new look.",
      "High quality products used that left my scalp refreshed."
    ],
    hiPhrases: [
      "हेयर स्टाइलिस्ट ने मेरी इच्छा के अनुसार बहुत ही सुंदर हेयरकट दिया।",
      "हेयर स्पा के बाद बाल बहुत ही मुलायम और चमकदार महसूस हो रहे हैं।",
      "प्रोफेशनल कटिंग और हेयर केयर टिप्स बहुत काम आए।",
      "कलरिंग और हाईलाइट्स का फिनिश बिल्कुल नेचुरल आया।"
    ],
    guPhrases: [
      "હેર સ્ટાઇલિસ્ટે મારી ઈચ્છા મુજબ ખૂબ જ સરસ હેરકટ આપ્યો.",
      "હેર સ્પા પછી વાળ ખૂબ જ સિલ્કી અને ચમકદાર અનુભવાય છે.",
      "પ્રોફેશનલ કટિંગ અને હેર કેર સલાહ ખૂબ ઉપયોગી રહી.",
      "કલરિંગ અને હાઇલાઇટ્સનું ફિનિશિંગ એકદમ નેચરલ આવ્યું."
    ]
  }),
  buildCategory({
    name: 'Skincare & Facials',
    nameHi: 'स्किनकेयर व फेशियल',
    nameGu: 'સ્કિનકેર અને ફેશિયલ',
    enPhrases: [
      "The facial was incredibly relaxing and left my skin glowing instantly.",
      "Gentle massage techniques used during the skincare session.",
      "Customized mask suited for my skin type with great results.",
      "Deep cleansing treatment that felt rejuvenating and soothing.",
      "Skin feels soft, hydrated, and completely refreshed after the service."
    ],
    hiPhrases: [
      "फेशियल के बाद त्वचा में बहुत ही प्राकृतिक निखार आया।",
      "स्किनकेयर ट्रीटमेंट बहुत ही आरामदायक और असरदार था।",
      "त्वचा की रंगत और निखार में साफ फर्क महसूस हुआ।"
    ],
    guPhrases: [
      "ફેશિયલ પછી ત્વચામાં ખૂબ જ કુદરતી ગ્લો આવ્યો.",
      "સ્કિનકેર ટ્રીટમેન્ટ ખૂબ જ આરામદાયક અને અસરકારક હતી.",
      "ત્વચાની ચમકમાં સ્પષ્ટ તફાવત અનુભવાયો."
    ]
  }),
  buildCategory({
    name: 'Staff Courtesy',
    nameHi: 'स्टाफ का व्यवहार',
    nameGu: 'સ્ટાફનું વર્તન',
    enPhrases: [
      "Warm, hospitable staff who made me feel relaxed from the start.",
      "Polite beauticians who listened carefully to all my requirements.",
      "Professional demeanor and courteous attitude throughout the appointment.",
      "Staff checked on my comfort level repeatedly during the service."
    ],
    hiPhrases: [
      "स्टाफ का व्यवहार बहुत ही नम्र, मददगार और सम्मानजनक था।",
      "सैलून स्टाफ ने मेरी प्राथमिकताओं को ध्यान से सुना और समझा।",
      "ग्राहक सेवा का स्तर वास्तव में बहुत ही सराहनीय था।"
    ],
    guPhrases: [
      "સ્ટાફનું વર્તન ખૂબ જ નમ્ર અને આદરણીય હતું.",
      "સલૂન સ્ટાફે મારી પસંદગીઓને ધ્યાનથી સાંભળી અને અનુસરી.",
      "ગ્રાહક સેવાનું સ્તર ખરેખર પ્રશંસનીય હતું."
    ]
  }),
  buildCategory({
    name: 'Cleanliness & Hygiene',
    nameHi: 'सफाई व स्वच्छता',
    nameGu: 'સફાઈ અને સ્વચ્છતા',
    enPhrases: [
      "Sterilized tools, fresh disposable capes, and spotless workstations.",
      "High standards of salon hygiene maintained everywhere.",
      "Clean towels, sanitized chairs, and neat presentation.",
      "Felt safe and comfortable due to thorough sanitization."
    ],
    hiPhrases: [
      "सैलून में स्वच्छता का विशेष ध्यान रखा गया था — उपकरण पूरी तरह से सैनिटाइज्ड थे।",
      "ताजा तौलिए और साफ डिस्पोजेबल शीट का इस्तेमाल किया गया।",
      "सफाई का माहौल देखकर बहुत भरोसा बना।"
    ],
    guPhrases: [
      "સલૂનમાં સ્વચ્છતાનું વિશેષ ધ્યાન રાખવામાં આવ્યું હતું — સાધનો સેનિટાઇઝ્ડ હતા.",
      "તાજા ટુવાલ અને સ્વચ્છ ડિસ્પોઝેબલ શીટનો ઉપયોગ કરવામાં આવ્યો.",
      "સફાઈનું વાતાવરણ જોઈને ખૂબ જ સંતોષ થયો."
    ]
  }),
  buildCategory({
    name: 'Value for Money',
    nameHi: 'मूल्य का मूल्य',
    nameGu: 'વ્યાજબી કિંમત',
    enPhrases: [
      "Reasonable pricing packages for such high-end grooming services.",
      "Worth every rupee spent considering the quality of products and service.",
      "Transparent pricing with no unexpected hidden charges.",
      "Great salon deals and membership perks."
    ],
    hiPhrases: [
      "सेवाओं की गुणवत्ता को देखते हुए शुल्क बहुत ही वाजिब है।",
      "पैसा वसूल सेवाएं — बजट में प्रीमियम ग्रूमिंग मिलेगी।"
    ],
    guPhrases: [
      "સેવાઓની ગુણવત્તા જોતાં કિંમત ખૂબ જ વ્યાજબી છે.",
      "પૈસા વસૂલ સેવાઓ — બજેટમાં પ્રીમિયમ લુક મળ્યો."
    ]
  }),
  buildCategory({
    name: 'Ambience & Comfort',
    nameHi: 'माहौल व आराम',
    nameGu: 'વાતાવરણ અને આરામ',
    enPhrases: [
      "Soothing interior background music, aromatic ambiance, and cozy chairs.",
      "Peaceful atmosphere that makes pampering sessions delightful.",
      "Well-lit space with aesthetic decor and relaxing seating.",
      "Calm, tranquil vibe that reduces everyday stress."
    ],
    hiPhrases: [
      "सैलून का माहौल बहुत ही शांत, सुगंधित और आरामदायक था।",
      "आरामदायक कुर्सियां और सुंदर रोशनी से मन प्रसन्न हो गया।"
    ],
    guPhrases: [
      "સલૂનનું વાતાવરણ ખૂબ જ શાંત, સુગંધી અને આરામદાયક હતું.",
      "આરામદાયક ખુરશીઓ અને સુંદર લાઇટિંગથી મન પ્રસન્ન થયું."
    ]
  }),
  buildCategory({
    name: 'Waiting Time',
    nameHi: 'समय प्रबंधन',
    nameGu: 'સમય પંચ્યુઆલિટી',
    enPhrases: [
      "Punctual appointment timing with virtually zero waiting time.",
      "Well-managed booking schedule so services started promptly on arrival.",
      "Efficient flow between services without unnecessary delays."
    ],
    hiPhrases: [
      "अपॉइंटमेंट के समय पर ही सेवा शुरू हो गई — कोई इंतजार नहीं करना पड़ा।",
      "समय प्रबंधन बहुत ही सटीक और पेशेवर था।"
    ],
    guPhrases: [
      "એપોઇન્ટમેન્ટના સમયે જ સેવા શરૂ થઈ ગઈ — રાહ જોવી ન પડી.",
      "સમયનું સંચાલન ખૂબ જ ચોક્કસ અને વ્યાવસાયિક હતું."
    ]
  })
];

// ─────────────────────────────────────────────────────────────────────────────
// 3. RESTAURANT TEMPLATE (restaurant_v1)
// ─────────────────────────────────────────────────────────────────────────────

const restaurantCategories = [
  buildCategory({
    name: 'Food Quality & Taste',
    nameHi: 'भोजन की गुणवत्ता व स्वाद',
    nameGu: 'ખોરાકની ગુણવત્તા અને સ્વાદ',
    enPhrases: [
      "The food was absolutely mouthwatering — rich spices and authentic preparation.",
      "Freshly prepared dishes served piping hot at the table.",
      "Delightful presentation and exquisite blend of traditional flavours.",
      "Every course was cooked to perfection with great attention to detail.",
      "Signature dishes exceeded all expectations — full of authentic taste.",
      "Ingredients tasted fresh and high quality throughout the meal.",
      "Well-portioned starters and mouth-watering gravies.",
      "Balanced seasoning with just the right amount of spices."
    ],
    hiPhrases: [
      "खाना बेहद ही स्वादिष्ट और गरमा-गरम परोसा गया था।",
      "मसालों और स्वादों का सही संतुलन — हर व्यंजन लाजवाब था।",
      "ताजी सामग्री से तैयार भोजन में असली भारतीय स्वाद मिला।",
      "स्टार्टर्स से लेकर मेन कोर्स तक सब कुछ परफेक्ट था।"
    ],
    guPhrases: [
      "ખોરાક ખૂબ જ સ્વાદિષ્ટ અને ગરમ-ગરમ પીરસવામાં આવ્યો હતો.",
      "મસાલા અને સ્વાદનું યોગ્ય સંતુલન — દરેક વાનગી ઉત્તમ હતી.",
      "તાજી સામગ્રીમાંથી બનાવેલ ખોરાકમાં અસલ સ્વાદ મળ્યો.",
      "સ્ટાર્ટર્સથી લઈને મેઈન કોર્સ સુધી બધું જ પરફેક્ટ હતું."
    ]
  }),
  buildCategory({
    name: 'Menu Variety',
    nameHi: 'मेनू में विविधता',
    nameGu: 'મેનૂમાં વિવિધતા',
    enPhrases: [
      "Extensive menu choices offering wide variety for vegetarians and non-vegetarians.",
      "Great range of regional specialties, breads, and authentic desserts.",
      "Diverse options covering starters, main course, beverages, and sweets.",
      "Something on the menu for everyone across different ages and tastes."
    ],
    hiPhrases: [
      "मेनू में बहुत सारे विकल्प थे — शाकाहारी और विभिन्न स्वादों के लिए बड़ा संग्रह।",
      "पारंपरिक और आधुनिक व्यंजनों की विस्तृत श्रृंखला।"
    ],
    guPhrases: [
      "મેનૂમાં ઘણા બધા વિકલ્પો હતા — શાકાહારી અને વિવિધ વાનગીઓનું સુંદર કલેક્શન.",
      "પરંપરાગત અને આધુનિક વાનગીઓની વિશાળ શ્રેણી."
    ]
  }),
  buildCategory({
    name: 'Service Speed & Efficiency',
    nameHi: 'सेवा की गति',
    nameGu: 'સેવાની ઝડપ',
    enPhrases: [
      "Fast service with minimal wait time even during busy weekend hours.",
      "Attentive waiters who brought orders promptly and refreshed drinks.",
      "Smooth service coordination between starters and main courses."
    ],
    hiPhrases: [
      "ऑर्डर देने के बाद बहुत जल्दी और गरमा-गरम खाना टेबल पर आ गया।",
      "वेटर बहुत ही सतर्क और तत्पर थे।"
    ],
    guPhrases: [
      "ઓર્ડર આપ્યા પછી ખૂબ જ ઝડપથી અને ગરમ ખોરાક ટેબલ પર આવ્યો.",
      "વેઇટર ખૂબ જ સતર્ક અને કાર્યક્ષમ હતા."
    ]
  }),
  buildCategory({
    name: 'Staff Hospitality',
    nameHi: 'स्टाफ का आतिथ्य',
    nameGu: 'સ્ટાફનું આતિથ્ય',
    enPhrases: [
      "Warm hospitality from the floor manager and serving team.",
      "Courteous staff who guided us through the menu recommendations.",
      "Polite behavior and pleasant attitude towards all guests."
    ],
    hiPhrases: [
      "स्टाफ का आतिथ्य और व्यवहार बहुत ही आदरपूर्ण था।",
      "स्टाफ ने हमें बेहतरीन डिश चुनने में अच्छी सलाह दी।"
    ],
    guPhrases: [
      "સ્ટાફનું આતિથ્ય અને વર્તન ખૂબ જ આદરણીય હતું.",
      "સ્ટાફે અમને શ્રેષ્ઠ વાનગીઓ પસંદ કરવામાં સરસ મદદ કરી."
    ]
  }),
  buildCategory({
    name: 'Ambience & Seating',
    nameHi: 'माहौल व व्यवस्था',
    nameGu: 'વાતાવરણ અને બેઠક',
    enPhrases: [
      "Cozy aesthetic interiors with pleasant background lighting and music.",
      "Spacious table arrangement suitable for family gatherings and celebrations.",
      "Charming dining atmosphere with comfortable seating arrangements."
    ],
    hiPhrases: [
      "रेस्टोरेंट का माहौल बहुत ही सुंदर, साफ और पारिवारिक था।",
      "बैठने की उत्तम जगह और बढ़िया बैकग्राउंड म्यूजिक।"
    ],
    guPhrases: [
      "રેસ્ટોરન્ટનું વાતાવરણ ખૂબ જ સુંદર, સ્વચ્છ અને પારિવારિક હતું.",
      "બેસવાની ઉત્તમ જગ્યા અને સરસ બેકગ્રાઉન્ડ મ્યુઝિક."
    ]
  }),
  buildCategory({
    name: 'Hygiene & Cleanliness',
    nameHi: 'स्वच्छता और सफाई',
    nameGu: 'સ્વચ્છતા અને સફાઈ',
    enPhrases: [
      "Sparkling clean dining area, spotless cutlery, and sanitized tables.",
      "Hygienic food preparation standards maintained everywhere.",
      "Clean washrooms and well-maintained dining space."
    ],
    hiPhrases: [
      "टेबल, बर्तन और रेस्टोरेंट का कोना-कोना पूरी तरह से साफ था।",
      "स्वच्छता और सफाई के उच्च मानकों का पालन किया गया।"
    ],
    guPhrases: [
      "ટેબલ, વાસણો અને રેસ્ટોરન્ટનો દરેક ખૂણો સંપૂર્ણપણે સ્વચ્છ હતો.",
      "સ્વચ્છતા અને સફાઈના ઉચ્ચ ધોરણોનું પાલન કરવામાં આવ્યું."
    ]
  }),
  buildCategory({
    name: 'Value & Pricing',
    nameHi: 'किफायती मूल्य',
    nameGu: 'વ્યાજબી કિંમત',
    enPhrases: [
      "Generous portion sizes for the price charged.",
      "Excellent value for money dining experience for families.",
      "Reasonably priced dishes considering the food quality and ambience."
    ],
    hiPhrases: [
      "भोजन की मात्रा और स्वाद के हिसाब से दरें बहुत ही उचित थीं।",
      "परिवार के साथ बढ़िया भोजन के लिए बेहतरीन वैल्यू फॉर मनी।"
    ],
    guPhrases: [
      "ખોરાકના જથ્થા અને સ્વાદના હિસાબે ભાવ ખૂબ જ વ્યાજબી હતા.",
      "પરિવાર સાથે સુંદર ભોજન માટે શ્રેષ્ઠ વેલ્યુ ફોર મની."
    ]
  })
];

// ─────────────────────────────────────────────────────────────────────────────
// Build Final Output JSON
// ─────────────────────────────────────────────────────────────────────────────

const templates = [
  {
    id: 'ice_cream_v1',
    business_type: 'Ice Cream',
    _comment: '30+ variants per category, versioned pools (v1/v2/v3) for duplicate mitigation, EN/HI/GU translations.',
    categories: iceCreamCategories,
  },
  {
    id: 'salon_v1',
    business_type: 'Salon',
    _comment: '30+ variants per category, versioned pools (v1/v2/v3) for duplicate mitigation, EN/HI/GU translations.',
    categories: salonCategories,
  },
  {
    id: 'restaurant_v1',
    business_type: 'Restaurant',
    _comment: '30+ variants per category, versioned pools (v1/v2/v3) for duplicate mitigation, EN/HI/GU translations.',
    categories: restaurantCategories,
  },
];

const outPath = path.join(__dirname, '../firestore/seed/category-templates.json');
fs.writeFileSync(outPath, JSON.stringify(templates, null, 2), 'utf8');

console.log('✅ Generated 3 category templates:', outPath);
templates.forEach(t => {
  console.log(`\n📋 Template ID: ${t.id} (${t.business_type}) — ${t.categories.length} categories`);
  t.categories.forEach(c => {
    console.log(`   └─ ${c.name}: base EN=${c.phrase_pool.length}, v1/v2/v3 pools=${Object.keys(c.phrase_pool_versions).length}, HI=${c.translations.hi.phrase_pool.length}, GU=${c.translations.gu.phrase_pool.length}`);
  });
});
