/**
 * reviewGenerator.ts
 *
 * Cloud Functions & Service for AI-Generated Review System using Groq (llama-3.1-8b-instant).
 *
 * Dynamic Business Domain & Service vs. Product Reasoning:
 *   - Uses exact enrolled Business Category & Business Name.
 *   - Services (Salon, Clinic, Garage, Spa, Gym, Cleaning, etc.) CANNOT be ordered or tasted.
 *   - Products/Food (Restaurant, Cafe, Bakery, etc.) can be ordered and tasted.
 *   - Retail (Clothing, Jewelry, Electronics, etc.) are shopped and purchased.
 *   - 3-level chip capture with level semantics:
 *       * Level 1: Core Service / Product
 *       * Level 2: Specific Quality / Technique / Feature
 *       * Level 3: Overall Visit / Hospitality / Staff / Value for Money
 *   - Grammatically verified in English and Roman-script Hinglish.
 */

import {onRequest, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import * as crypto from "crypto";
import {groqApiKey} from "./secrets.js";

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Cleans and normalizes a chip label:
 * - Strips leading emojis and symbols
 * - Collapses whitespace
 * - Converts to lowercase for consistent sorting
 */
export function cleanChip(chip: string): string {
  if (!chip) return "";
  return chip
    .trim()
    // eslint-disable-next-line no-misleading-character-class
    .replace(/^[\p{Extended_Pictographic}\u200d\uFE0F•\-★✦✨#+>/~`!@$%^&*()_=[\]{}|;:'",.<>?]+/u, "")
    .replace(/^[^\w\s]+/u, "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

/**
 * Computes the deterministic SHA256 cache document ID for a given set of chips and business category.
 * All languages (English & Hinglish) for the same combination are stored in this single document.
 */
export function computeReviewCacheKey(
  chips: string[],
  businessCategory?: string
): {rawKey: string; docId: string; sortedChips: string[]} {
  const cleaned = chips
    .map(cleanChip)
    .filter((c) => c.length > 0);

  // Deduplicate and sort alphabetically
  const sortedChips = Array.from(new Set(cleaned)).sort((a, b) => a.localeCompare(b));
  const catPrefix = businessCategory ? cleanChip(businessCategory) : "";
  const rawKey = catPrefix ? `${catPrefix}::${sortedChips.join("|")}` : sortedChips.join("|");
  const docId = crypto.createHash("sha256").update(rawKey).digest("hex");

  return {rawKey, docId, sortedChips};
}

// ─── Dynamic Business Classification ────────────────────────────────────────

export type DomainClassification = "service" | "food" | "retail" | "general";

export interface BusinessContext {
  domainType: DomainClassification;
  isService: boolean;
  isFood: boolean;
  isRetail: boolean;
  categoryName: string;
  businessName: string;
}

export function classifyBusiness(
  category?: string,
  businessName?: string,
  chips: string[] = []
): BusinessContext {
  const catStr = (category || "").trim();
  const bizStr = (businessName || "").trim();
  const combined = `${catStr} ${bizStr} ${chips.join(" ")}`.toLowerCase();

  const serviceKeywords = [
    "salon", "spa", "parlour", "parlor", "barber", "hair", "haircut", "hairwash", "styling",
    "facial", "beauty", "makeup", "grooming", "waxing", "skin", "nail", "pedicure", "manicure",
    "clinic", "dental", "dentist", "doctor", "medical", "physio", "hospital", "therapy", "consult",
    "auto", "car", "garage", "bike", "repair", "service", "detailing", "mechanic", "wash", "coating",
    "denting", "painting", "ppf", "ceramic", "wheel", "alignment", "oil change", "suspension",
    "gym", "fitness", "yoga", "trainer", "studio", "cleaning", "plumb", "electric", "tailor",
    "laundry", "dry clean", "consulting", "agency", "tattoo", "photography", "hotel", "resort",
    "it", "software", "tech", "technology", "developer", "development", "web", "app", "cloud",
    "devops", "cyber", "network", "computer", "laptop", "hardware", "data recovery", "it support",
    "programming", "code",
  ];

  const foodKeywords = [
    "restaurant", "cafe", "coffee", "tea", "bakery", "food", "dining", "sweet", "chaat",
    "pizza", "burger", "ice cream", "dessert", "bistro", "dhaba", "bar", "pub", "kitchen",
    "biryani", "cater", "snack", "tiffin", "roll", "shawarma", "sandwich", "dosa", "roti", "meal",
  ];

  const retailKeywords = [
    "retail", "shop", "store", "clothing", "apparel", "fashion", "jewel", "jewellery", "footwear",
    "shoes", "optics", "eyewear", "furniture", "mart", "supermarket", "boutique", "electronics",
    "bookstore", "gift", "hardware", "florist", "flower",
  ];

  const isExplicitService = serviceKeywords.some((kw) => combined.includes(kw));
  const isExplicitFood = foodKeywords.some((kw) => combined.includes(kw));
  const isExplicitRetail = retailKeywords.some((kw) => combined.includes(kw));

  let domainType: DomainClassification = "general";
  if (isExplicitService && !isExplicitFood) {
    domainType = "service";
  } else if (isExplicitFood && !isExplicitService) {
    domainType = "food";
  } else if (isExplicitRetail && !isExplicitFood && !isExplicitService) {
    domainType = "retail";
  } else {
    // If ambiguous or mixed, check category string specifically
    const catLower = catStr.toLowerCase();
    if (serviceKeywords.some((kw) => catLower.includes(kw))) {
      domainType = "service";
    } else if (foodKeywords.some((kw) => catLower.includes(kw))) {
      domainType = "food";
    } else if (retailKeywords.some((kw) => catLower.includes(kw))) {
      domainType = "retail";
    } else {
      domainType = "general";
    }
  }

  return {
    domainType,
    isService: domainType === "service",
    isFood: domainType === "food",
    isRetail: domainType === "retail",
    categoryName: catStr || "General",
    businessName: bizStr || "",
  };
}

/**
 * Validates that a generated or cached review is grammatically and semantically sound:
 * - Services must NEVER say "ordered", "taste", "delicious", "food", "piping hot", etc.
 * - Non-food businesses must not have food vocabulary.
 * - Reviews must not contain template placeholders or nonsense formatting.
 */
export function isReviewSensibleAndValid(review: string, context: BusinessContext): boolean {
  if (!review || typeof review !== "string") return false;
  const trimmed = review.trim();
  if (trimmed.length < 15 || trimmed.length > 350) return false;

  const l = trimmed.toLowerCase();

  // If this is a service business (e.g. salon, dental clinic, garage, gym)
  if (context.isService) {
    const forbiddenInService = [
      "ordered the",
      "ordered a ",
      "ordered my",
      "ordered some",
      "we ordered",
      "i ordered",
      "order kiya",
      "order kara",
      "order kiye",
      "order karke",
      "authentic taste",
      "delicious taste",
      "great taste",
      "taste was",
      "tasty",
      "tasty food",
      "delicious food",
      "bursting with flavor",
      "rich flavor",
      "piping hot",
      "food was",
      "food is",
      "food ekdum",
      "culinary",
      "dining here",
      "dining experience",
      "meal was",
      "meal here",
      "mouthwatering",
      "served hot",
      "dish was",
      "dishes were",
      "recipe",
      "tasted great",
      "eating here",
    ];
    for (const term of forbiddenInService) {
      if (l.includes(term)) return false;
    }
  }

  // Common template / code artifacts
  const codeArtifacts = [
    "undefined",
    "null",
    "lorem ipsum",
    "placeholder",
    "[business",
    "{business",
    "[insert",
    "{insert",
    "level 1",
    "level 2",
    "level 3",
    "step 1",
    "step 2",
    "step 3",
  ];
  for (const art of codeArtifacts) {
    if (l.includes(art)) return false;
  }

  return true;
}

// ─── Semantic Chip Profiler ──────────────────────────────────────────────────

export interface ReviewSelectionLevels {
  step1?: string[]; // Core Product / Service (e.g. "Layered Haircut", "Margherita Pizza")
  step2?: string[]; // Specific Highlight / Technique (e.g. "Perfect Frame Layers", "Extra Cheese")
  step3?: string[]; // Experience / Staff / Value (e.g. "Warm Hospitality", "Value for Money")
  chips?: string[]; // Flat list fallback
}

function formatItemList(items: string[]): string {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0];
  if (items.length === 2) return `${items[0]} and ${items[1]}`;
  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
}

export interface SemanticProfile {
  items: string[];
  qualities: string[];
  staff: string[];
  ambiance: string[];
  service: string[];
  pricing: string[];
  hygiene: string[];
  general: string[];
}

export function categorizeChips(levels: ReviewSelectionLevels): SemanticProfile {
  const hasStructured = (levels.step1 && levels.step1.length > 0) ||
                        (levels.step2 && levels.step2.length > 0) ||
                        (levels.step3 && levels.step3.length > 0);

  const profile: SemanticProfile = {
    items: (levels.step1 || []).map(cleanChip).filter(Boolean),
    qualities: (levels.step2 || []).map(cleanChip).filter(Boolean),
    staff: [],
    ambiance: [],
    service: [],
    pricing: [],
    hygiene: [],
    general: [],
  };

  const expChips: string[] = (levels.step3 || []).map(cleanChip).filter(Boolean);

  if (!hasStructured && levels.chips && levels.chips.length > 0) {
    const flat = levels.chips.map(cleanChip).filter(Boolean);
    for (let i = 0; i < flat.length; i++) {
      const c = flat[i];
      const l = c.toLowerCase();
      const isExp = l.includes("staff") || l.includes("barista") || l.includes("stylist") || l.includes("doctor") || l.includes("mechanic") || l.includes("crew") || l.includes("polite") || l.includes("helpful") || l.includes("courteous") || l.includes("welcoming") ||
                    l.includes("ambience") || l.includes("vibe") || l.includes("atmosphere") || l.includes("music") || l.includes("seating") || l.includes("cozy") ||
                    l.includes("service") || l.includes("fast") || l.includes("quick") || l.includes("speed") ||
                    l.includes("value") || l.includes("money") || l.includes("pocket") || l.includes("price") || l.includes("pricing") || l.includes("budget") || l.includes("affordable") || l.includes("paisa vasool") ||
                    l.includes("clean") || l.includes("hygiene") || l.includes("spotless") || l.includes("sanitized") || l.includes("hospitality");

      if (isExp) {
        expChips.push(c);
      } else if (profile.items.length === 0) {
        profile.items.push(c);
      } else if (profile.qualities.length === 0) {
        profile.qualities.push(c);
      } else {
        profile.qualities.push(c);
      }
    }
  }

  for (const c of expChips) {
    const l = c.toLowerCase();
    if (l.includes("staff") || l.includes("stylist") || l.includes("doctor") || l.includes("barista") || l.includes("captain") || l.includes("crew") || l.includes("polite") || l.includes("helpful") || l.includes("courteous") || l.includes("welcoming") || l.includes("humble") || l.includes("hospitality")) {
      profile.staff.push(c);
    } else if (l.includes("ambience") || l.includes("vibe") || l.includes("atmosphere") || l.includes("music") || l.includes("seating") || l.includes("decor") || l.includes("cozy") || l.includes("aesthetic") || l.includes("lighting")) {
      profile.ambiance.push(c);
    } else if (l.includes("service") || l.includes("fast") || l.includes("quick") || l.includes("speed") || l.includes("punctual") || l.includes("turnaround")) {
      profile.service.push(c);
    } else if (l.includes("value") || l.includes("money") || l.includes("pocket") || l.includes("price") || l.includes("pricing") || l.includes("budget") || l.includes("affordable") || l.includes("worth") || l.includes("paisa vasool") || l.includes("fair")) {
      profile.pricing.push(c);
    } else if (l.includes("clean") || l.includes("hygiene") || l.includes("sanitized") || l.includes("spotless") || l.includes("tidy")) {
      profile.hygiene.push(c);
    } else {
      profile.general.push(c);
    }
  }

  return profile;
}

// ─── Dynamic Local Fallback Engine (10 Diverse Perspectives) ───────────────

export function generateLocalFallbackReviews(
  levels: ReviewSelectionLevels,
  language: "english" | "hinglish",
  count = 10,
  businessCategory?: string,
  businessName?: string
): string[] {
  const s1Clean = (levels.step1 || []).map(cleanChip).filter(Boolean);
  const s2Clean = (levels.step2 || []).map(cleanChip).filter(Boolean);
  const s3Clean = (levels.step3 || []).map(cleanChip).filter(Boolean);
  const flat = (levels.chips || []).map(cleanChip).filter(Boolean);

  const allSelected = Array.from(new Set([...s1Clean, ...s2Clean, ...s3Clean, ...flat]));
  const context = classifyBusiness(businessCategory, businessName, allSelected);

  const serviceName = s1Clean.length > 0 ? formatItemList(s1Clean) : (flat.length > 0 ? flat[0] : (context.isService ? "the service" : "the visit"));

  const expPool = Array.from(new Set([
    ...s2Clean,
    ...s3Clean,
    ...flat.filter((c) => !s1Clean.includes(c)),
  ]));

  // Default fallback tags per domain if no tags provided
  const defaultExpService = [
    "precise styling and technique",
    "skilled and attentive team",
    "spotless clean and sanitized setup",
    "complete value for money",
    "warm hospitality and zero wait",
    "long lasting finish and healthy look",
    "gentle care and professional advice",
    "relaxing atmosphere and comfortable vibe",
  ];

  const defaultExpFood = [
    "served hot and bursting with flavors",
    "polite and attentive service",
    "clean dining setup and cozy vibe",
    "very fair pricing and generous portion",
    "super fast preparation",
    "authentic taste and rich texture",
    "fresh ingredients and great presentation",
    "welcoming atmosphere for family and friends",
  ];

  const defaultExpRetail = [
    "premium quality and perfect fit",
    "helpful and patient store staff",
    "organized and beautiful store",
    "great discounts and fair pricing",
    "hassle-free checkout and billing",
    "wide variety and latest collection",
    "durable build and authentic items",
    "delightful shopping experience",
  ];

  const domainDefaults = context.isFood ? defaultExpFood : (context.isRetail ? defaultExpRetail : defaultExpService);
  const tags = expPool.length >= 3 ? expPool : [...expPool, ...domainDefaults];

  const pool: string[] = [];

  if (language === "hinglish") {
    if (context.isFood) {
      pool.push(
        `Humne inka ${serviceName} try kiya — taste ekdum fresh aur lajawab tha with ${tags[0]}! 5 stars.`,
        `Visited today and ordered the ${serviceName}. Super delicious preparation aur ${tags[1] || "bohot polite staff"}! Highly recommended.`,
        `Had a wonderful meal! Inka ${serviceName} definitely try karna chahiye — ${tags[2] || "super clean seating"} ke saath poora experience 10/10 tha.`,
        `Inka ${serviceName} bohot tasty tha! Fair pricing aur ${tags[3] || "poora paisa vasool experience"} laga.`,
        `Recently visit kiya aur ${serviceName} order kiya tha. Food super fresh serve hua, loved the ${tags[4] || "quick service"}!`,
        `Great taste and wonderful flavors on the ${serviceName}! ${tags[5] || "Hospitality bohot achhi thi"}. 5/5 stars!`,
        `Loved every bite of the ${serviceName}! Preparation spot on thi with ${tags[6] || "rich taste"}. Must visit!`,
        `Inka ${serviceName} is an absolute must-try! Ambiance cozy hai aur ${tags[7] || "staff super helpful tha"}.`,
        `Thoroughly enjoyed the ${serviceName} today. Quality aur cleanliness dono top tier the. 5 stars!`,
        `Super fresh ${serviceName} with amazing flavors! Will definitely be visiting again soon.`
      );
    } else if (context.isService) {
      pool.push(
        `Humne inka ${serviceName} karwaya tha — execution aur finishing ekdum standout thi with ${tags[0]}! 5 stars.`,
        `Visited for ${serviceName} today! Super professional specialists aur ${tags[1] || "staff ka behavior bohot courteous tha"}. Highly recommended!`,
        `Had my ${serviceName} done here! Place bohot clean aur hygienic hai, plus ${tags[2] || "felt totally comfortable"}. 5/5 stars!`,
        `Loved their ${serviceName} service! Work quality 10/10 thi aur ${tags[3] || "pocket-friendly pricing ke saath poora paisa vasool"}!`,
        `Recently visit kiya aur ${serviceName} karwaya. Work super professional tha with ${tags[4] || "punctual handling"}.`,
        `Super skilled team aur great precision on the ${serviceName}! Results standout the with ${tags[5] || "long lasting finish"}.`,
        `Really enjoyed my session for ${serviceName} today! Gentle technique aur ${tags[6] || "honest consultation"} mila. 5 stars!`,
        `Inka ${serviceName} definitely recommended hai — peaceful vibe aur ${tags[7] || "warm hospitality"} throughout the visit.`,
        `Best place for ${serviceName}! Precision aur care standout the. 10/10 experience!`,
        `Super happy with my ${serviceName}! Flawless execution aur great results mile. Must visit!`
      );
    } else {
      pool.push(
        `Inka ${serviceName} liya — quality ekdum top notch thi with ${tags[0]}! 5 stars.`,
        `Visited for ${serviceName} today! Super helpful team aur ${tags[1] || "smooth experience"} mila. Highly recommended!`,
        `Great collection of ${serviceName}! ${tags[2] || "Organized showroom"} aur courteous staff. 5/5 stars!`,
        `Loved the ${serviceName}! Super fair pricing ke saath ${tags[3] || "complete value for money"} laga.`,
        `Smooth handling for ${serviceName} with ${tags[4] || "quick checkout"}. Highly satisfied!`,
        `Premium quality ${serviceName} with ${tags[5] || "durable build"}. Will definitely shop again!`,
        `Visited today and found the perfect ${serviceName}. ${tags[6] || "Staff gave great advice"}. 5 stars!`,
        `Delightful experience purchasing ${serviceName}. ${tags[7] || "Warm and welcoming team"}. Must visit!`,
        `Thoroughly impressed by the ${serviceName} and overall quality. 10/10!`,
        `Super satisfied with my ${serviceName}! Highly recommended.`
      );
    }
  } else {
    // English
    if (context.isFood) {
      pool.push(
        `Tried the ${serviceName} today — fresh, delicious, and highlighting ${tags[0]}! 5 stars.`,
        `Ordered the ${serviceName} and was thoroughly impressed by the ${tags[1] || "attentive hospitality"}. Highly recommended!`,
        `Had a wonderful meal! The ${serviceName} was packed with authentic flavors and ${tags[2] || "served in a cozy ambiance"}.`,
        `Loved the ${serviceName}! Generous portion, top quality, and ${tags[3] || "complete value for money"}. 5 stars!`,
        `The ${serviceName} was served piping hot with ${tags[4] || "super fast service"}. Fantastic dining experience!`,
        `Super fresh ingredients and great presentation on the ${serviceName}. ${tags[5] || "Rich and authentic taste"}. 5/5 stars!`,
        `If you visit, you must try their ${serviceName}! Delicious preparation and ${tags[6] || "courteous staff"}.`,
        `One of the best places for ${serviceName}! Loved the vibe and ${tags[7] || "prompt handling"}. Must visit!`,
        `Really enjoyed dining here today. The ${serviceName} was cooked to perfection. 5 stars!`,
        `Outstanding culinary experience with ${serviceName}. Will definitely be back for more!`
      );
    } else if (context.isService) {
      pool.push(
        `Got a ${serviceName} done here today! Flawless execution highlighting ${tags[0]}. 5 stars!`,
        `Booked a session for ${serviceName} — the specialists were very skilled and provided ${tags[1] || "wonderful hospitality"}. Highly recommended!`,
        `Had my ${serviceName} done here! Loved the spotless hygiene and ${tags[2] || "calm, soothing ambiance"}. 5/5 stars!`,
        `Loved their ${serviceName}! Top tier service and ${tags[3] || "very reasonable pricing with complete value for money"}.`,
        `Smooth appointment for ${serviceName} with ${tags[4] || "zero waiting time and prompt handling"}. Very pleased!`,
        `Precision and attention to detail on the ${serviceName}! The results were fantastic with ${tags[5] || "a long-lasting finish"}. 5 stars!`,
        `Such a rejuvenating experience with ${serviceName}! Appreciated the ${tags[6] || "expert advice and gentle technique"}.`,
        `Best place for ${serviceName}! The team made sure everything was comfortable, backed by ${tags[7] || "warm hospitality"}. 10/10!`,
        `Really happy with my ${serviceName}! Professional, courteous, and skilled specialists throughout. 5 stars!`,
        `Outstanding service on the ${serviceName} from start to finish. Will definitely be coming back!`
      );
    } else {
      pool.push(
        `Purchased the ${serviceName} today — exceptional quality featuring ${tags[0]}. 5 stars!`,
        `Visited for ${serviceName} and received wonderful assistance with ${tags[1] || "friendly staff"}. Highly recommended!`,
        `Great variety and neat store setup for ${serviceName}. Appreciated the ${tags[2] || "clean ambiance"}. 5/5 stars!`,
        `Loved the ${serviceName}! Very fair pricing with ${tags[3] || "complete value for money"}. 5 stars!`,
        `Quick and seamless checkout for ${serviceName} with ${tags[4] || "prompt service"}. Very happy!`,
        `Premium build and top craftsmanship on the ${serviceName} with ${tags[5] || "durable quality"}. 10/10!`,
        `Found exactly what I was looking for in ${serviceName}. ${tags[6] || "Patient and helpful team"}. 5 stars!`,
        `Delightful shopping trip for ${serviceName}. Loved the ${tags[7] || "welcoming atmosphere"}. Must visit!`,
        `Thoroughly impressed by their ${serviceName} collection. 5/5 stars!`,
        `Super satisfied with my purchase of ${serviceName}. Highly recommended!`
      );
    }
  }

  return pool.slice(0, count);
}

// ─── Groq API Caller (llama-3.1-8b-instant) ──────────────────────────────────

export async function callGroqLlamaReviewBatch(
  levels: ReviewSelectionLevels,
  language: "english" | "hinglish",
  apiKey?: string,
  businessCategory?: string,
  businessName?: string
): Promise<string[]> {
  const key = apiKey || process.env.GROQ_API_KEY;

  const s1Clean = (levels.step1 || []).map(cleanChip).filter(Boolean);
  const s2Clean = (levels.step2 || []).map(cleanChip).filter(Boolean);
  const s3Clean = (levels.step3 || []).map(cleanChip).filter(Boolean);
  const flat = (levels.chips || []).map(cleanChip).filter(Boolean);

  const serviceChips = s1Clean.length > 0 ? s1Clean : flat.slice(0, 1);
  const s1List = serviceChips.join(", ");

  // Collect all available experience tags
  const experienceTags = Array.from(new Set([
    ...s2Clean,
    ...s3Clean,
    ...flat.filter((c) => !serviceChips.includes(c)),
  ]));
  const expList = experienceTags.join(", ");

  const allSelectedUnique = Array.from(
    new Set([...s1Clean, ...s2Clean, ...s3Clean, ...flat])
  );
  const context = classifyBusiness(businessCategory, businessName, allSelectedUnique);

  if (!key) {
    logger.warn("No GROQ_API_KEY available; using local fallback generator");
    return generateLocalFallbackReviews(levels, language, 10, businessCategory, businessName);
  }

  let domainInstructions = "";
  if (context.isService) {
    domainInstructions =
      `BUSINESS TYPE: SERVICE BUSINESS (Category: "${context.categoryName}", Business: "${context.businessName || "Service Provider"}").\n` +
      "CRITICAL SERVICE RULES:\n" +
      "1. SERVICES CANNOT BE ORDERED, TASTED, OR CONSUMED LIKE FOOD!\n" +
      "2. ACTION VERBS FOR SERVICES: 'got a [service] done', 'visited for [service]', 'had my [service] done/styled/treated/serviced', 'booked an appointment for [service]', 'opted for [service]'.\n" +
      "3. SERVICE OUTCOMES: 'flawless styling', 'precision finishing', 'skilled specialists', 'felt rejuvenated', 'clean execution', 'rejuvenating experience'.\n" +
      "4. STRICTLY FORBIDDEN FOR SERVICES: 'ordered', 'we ordered', 'delicious', 'authentic taste', 'piping hot', 'great flavor', 'culinary', 'dish', 'meal', 'tasty'.";
  } else if (context.isFood) {
    domainInstructions =
      `BUSINESS TYPE: FOOD & DINING (Category: "${context.categoryName}", Business: "${context.businessName || "Restaurant/Cafe"}").\n` +
      "FOOD RULES:\n" +
      "1. Customers order dishes, taste flavors, and enjoy meals.\n" +
      "2. ACTION VERBS: 'ordered', 'tried', 'had the [dish]'.\n" +
      "3. QUALITIES: 'fresh and flavorful', 'authentic taste', 'served hot and delicious'.";
  } else if (context.isRetail) {
    domainInstructions =
      `BUSINESS TYPE: RETAIL & SHOPPING (Category: "${context.categoryName}", Business: "${context.businessName || "Store/Shop"}").\n` +
      "RETAIL RULES:\n" +
      "1. Customers purchase items, shop for collections, check fitting/quality.\n" +
      "2. ACTION VERBS: 'bought', 'purchased', 'picked up', 'checked out their collection'.\n" +
      "3. QUALITIES: 'premium fabric/build', 'great variety', 'perfect fit and finish'.";
  } else {
    domainInstructions =
      `BUSINESS TYPE: GENERAL BUSINESS (Category: "${context.categoryName}", Business: "${context.businessName || "Business"}").\n` +
      "RULES: Match action verbs naturally to what the customer experienced.";
  }

  let systemPrompt = "";
  let userPrompt = "";

  if (language === "hinglish") {
    systemPrompt =
      "You are an expert AI creating 10 hyper-realistic, diverse Google Maps reviews in conversational Roman-script Hinglish (English alphabet only, NO Hindi Devanagari script).\n\n" +
      domainInstructions + "\n\n" +
      "MANDATORY DIVERSITY REQUIREMENT ACROSS ALL 10 REVIEWS:\n" +
      "Each of the 10 reviews MUST highlight DIFFERENT experiences, aspects, and impressions of the visit:\n" +
      "• Review 1: Focus on execution quality & technique/finish\n" +
      "• Review 2: Focus on staff behavior, politeness & warm hospitality\n" +
      "• Review 3: Focus on cleanliness, spotless hygiene & comfortable vibe\n" +
      "• Review 4: Focus on reasonable pricing & total value for money (poora paisa vasool)\n" +
      "• Review 5: Focus on turnaround time, punctuality & smooth consultation\n" +
      "• Review 6: Focus on long-lasting results & personal satisfaction\n" +
      "• Review 7: Focus on expert advice & attentive team\n" +
      "• Review 8: Focus on cozy ambience & refreshing experience\n" +
      "• Review 9: Focus on precision, attention to detail & high standards\n" +
      "• Review 10: Focus on overall 5-star rating & strong recommendation to friends/family\n\n" +
      "GRAMMAR & SYNTHESIS RULES:\n" +
      "1. NO TEMPLATE FRAMES: Write natural, fluid spoken Hinglish prose (1-3 natural sentences per review, 18-35 words).\n" +
      "2. HINDI GENDER & VERB AGREEMENT: 'tha' for service/haircut/visit, 'thi' for quality/styling/hospitality, 'the' for staff/specialists/rates.\n" +
      "3. FOR VALUE FOR MONEY: Say 'prices kaafi reasonable the aur poora paisa vasool experience tha' or 'super affordable rates ke saath complete value for money laga'.\n" +
      "4. VARY OPENINGS, SENTENCE LENGTHS, AND VOCABULARY ACROSS ALL 10 REVIEWS.\n" +
      "5. 100% BUSINESS-AGNOSTIC: NEVER invent store/brand/restaurant names.";

    userPrompt =
      "Synthesize the following customer selection into 10 completely diverse, distinct Hinglish Google reviews where EACH review highlights DIFFERENT experiences and positive aspects.\n\n" +
      "BUSINESS DETAILS:\n" +
      `• Category: "${context.categoryName}"\n` +
      `• Business Name: "${context.businessName || "Business"}"\n\n` +
      "CUSTOMER VISIT CONTEXT:\n" +
      `• Selected Service / Product: "${s1List || "Service"}"\n` +
      (expList ? `• Available Experience Tags & Highlights Pool: "${expList}"\n\n` : "\n") +
      "STRICT DIVERSITY REQUIREMENT:\n" +
      "Each of the 10 reviews must emphasize different tags/qualities from the available pool so no two reviews mention the same experience!\n\n" +
      "STRICT OUTPUT FORMAT:\n" +
      "Return ONLY valid JSON format: {\"reviews\": [\"review 1\", \"review 2\", ...]}";
  } else {
    // English
    systemPrompt =
      "You are an expert AI creating 10 hyper-realistic, diverse Google Maps reviews for real customers.\n\n" +
      domainInstructions + "\n\n" +
      "MANDATORY DIVERSITY REQUIREMENT ACROSS ALL 10 REVIEWS:\n" +
      "Each of the 10 reviews MUST highlight DIFFERENT experiences, aspects, and impressions of the visit:\n" +
      "• Review 1: Focus on quality of service / finish & technique\n" +
      "• Review 2: Focus on staff attentiveness, courtesy & warm hospitality\n" +
      "• Review 3: Focus on spotless hygiene, clean setup & comfortable ambience\n" +
      "• Review 4: Focus on fair pricing & complete value for money\n" +
      "• Review 5: Focus on punctuality, prompt turnaround & seamless appointment\n" +
      "• Review 6: Focus on long-lasting results & confidence boost\n" +
      "• Review 7: Focus on expert consultation & personalized guidance\n" +
      "• Review 8: Focus on soothing vibe & rejuvenating experience\n" +
      "• Review 9: Focus on attention to detail, precision & high craftsmanship\n" +
      "• Review 10: Focus on overall 5-star recommendation & returning soon\n\n" +
      "MANDATORY RULES:\n" +
      "1. NATURAL FLOW: First-person perspective ('I', 'We'). Natural, authentic, conversational tone (1-3 sentences per review, 18-35 words).\n" +
      "2. NO REPETITIVE ADJECTIVES: Vary vocabulary, openings, and structure across all 10 reviews.\n" +
      "3. 100% BUSINESS-AGNOSTIC: NEVER invent brand or store names.";

    userPrompt =
      "Synthesize the following customer selection into 10 completely diverse, distinct English Google reviews where EACH review highlights DIFFERENT experiences and positive aspects.\n\n" +
      "BUSINESS DETAILS:\n" +
      `• Category: "${context.categoryName}"\n` +
      `• Business Name: "${context.businessName || "Business"}"\n\n` +
      "CUSTOMER VISIT CONTEXT:\n" +
      `• Selected Service / Product: "${s1List || "Service"}"\n` +
      (expList ? `• Available Experience Tags & Highlights Pool: "${expList}"\n\n` : "\n") +
      "STRICT DIVERSITY REQUIREMENT:\n" +
      "Each of the 10 reviews must emphasize different tags/qualities from the available pool so no two reviews mention the same experience!\n\n" +
      "STRICT OUTPUT FORMAT:\n" +
      "Return ONLY valid JSON format: {\"reviews\": [\"review 1\", \"review 2\", ...]}";
  }

  try {
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "llama-3.1-8b-instant",
        messages: [
          {role: "system", content: systemPrompt},
          {role: "user", content: userPrompt},
        ],
        temperature: 0.75,
        max_tokens: 850,
        response_format: {type: "json_object"},
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      logger.error(`Groq API error ${response.status}: ${errText}`);
      return generateLocalFallbackReviews(levels, language, 10, businessCategory, businessName);
    }

    const data = (await response.json()) as {
      choices?: Array<{message?: {content?: string}}>;
    };
    const content = data.choices?.[0]?.message?.content?.trim();

    if (!content) {
      logger.warn("Groq returned empty content; using fallback");
      return generateLocalFallbackReviews(levels, language, 10, businessCategory, businessName);
    }

    // Parse JSON
    let reviews: string[] = [];
    try {
      const parsed = JSON.parse(content);
      if (Array.isArray(parsed)) {
        reviews = parsed;
      } else if (parsed.reviews && Array.isArray(parsed.reviews)) {
        reviews = parsed.reviews;
      } else {
        const values = Object.values(parsed);
        const arrayVal = values.find((v) => Array.isArray(v));
        if (arrayVal) reviews = arrayVal as string[];
      }
    } catch {
      // Regex extraction fallback
      const matches = content.match(/"([^"\\]*(\\.[^"\\]*)*)"/g);
      if (matches && matches.length > 0) {
        reviews = matches.map((m) => m.replace(/^"|"$/g, "").replace(/\\"/g, "\"").trim());
      }
    }

    // Filter valid reviews with domain compliance & grammatical sensibility
    const cleanedReviews = reviews
      .map((r) => typeof r === "string" ? r.trim() : "")
      .filter((r) => isReviewSensibleAndValid(r, context));

    if (cleanedReviews.length >= 10) {
      return cleanedReviews.slice(0, 10);
    }

    logger.warn(`Groq produced ${cleanedReviews.length} valid reviews; supplementing with dynamic fallback`);
    const fallback = generateLocalFallbackReviews(levels, language, 10, businessCategory, businessName);
    return [...cleanedReviews, ...fallback].slice(0, 10);
  } catch (err) {
    logger.error("Error calling Groq API:", err);
    return generateLocalFallbackReviews(levels, language, 10, businessCategory, businessName);
  }
}

// ─── Cache Management & Serving Service ──────────────────────────────────────

export interface GetReviewResult {
  review: string;
  allReviews: string[];
  englishReviews?: string[];
  hinglishReviews?: string[];
  language: "english" | "hinglish" | "mixed";
  docId: string;
  source: "cache" | "generated_fresh" | "fallback";
  remainingCount: number;
}

/**
 * Gets or generates reviews based on selected chips, category, and language preference.
 * Stores English and Hinglish reviews in a single document for each combination.
 */
export async function getOrServeReview(params: {
  chips?: string[];
  step1?: string[];
  step2?: string[];
  step3?: string[];
  businessId?: string;
  businessName?: string;
  businessCategory?: string;
  archetype?: string;
  languagePref?: "english" | "hinglish" | "mixed";
  excludeCurrent?: string;
  apiKey?: string;
}): Promise<GetReviewResult> {
  const db = getFirestore();
  const {chips, step1, step2, step3, businessId, excludeCurrent, apiKey} = params;

  // Build combined chips array
  const allChips = chips && chips.length > 0 ?
    chips :
    [...(step1 || []), ...(step2 || []), ...(step3 || [])];

  const levels: ReviewSelectionLevels = {
    step1: (step1 || []).map(cleanChip).filter(Boolean),
    step2: (step2 || []).map(cleanChip).filter(Boolean),
    step3: (step3 || []).map(cleanChip).filter(Boolean),
    chips: allChips.map(cleanChip).filter(Boolean),
  };

  // 1. Resolve business language preference, name, and category
  let pref = params.languagePref;
  let businessName = params.businessName || "";
  let businessCategory = params.businessCategory || params.archetype || "";

  if (businessId) {
    try {
      const bizDoc = await db.collection("businesses").doc(businessId).get();
      if (bizDoc.exists) {
        const bizData = bizDoc.data();
        if (!pref) pref = bizData?.review_language_preference;
        if (!businessName) businessName = bizData?.brand_name || bizData?.brandName || bizData?.business_name || bizData?.name || "";
        if (!businessCategory) businessCategory = bizData?.category_type || bizData?.categoryType || bizData?.category || bizData?.default_category_template_id || bizData?.archetype || "";
      }
    } catch (e) {
      logger.warn(`Could not read business metadata for ${businessId}:`, e);
    }
  }

  const effectivePref: "english" | "hinglish" | "mixed" =
    (pref === "hinglish" || pref === "mixed") ? pref : "english";

  const context = classifyBusiness(businessCategory, businessName, allChips);

  // 2. Compute deterministic single SHA256 cache document ID based on business category and selected chips
  const {rawKey, docId, sortedChips} = computeReviewCacheKey(allChips, businessCategory);
  const cacheRef = db.collection("review_cache").doc(docId);

  try {
    const cacheSnap = await cacheRef.get();
    let englishReviews: string[] = [];
    let hinglishReviews: string[] = [];
    let isFresh = false;

    if (cacheSnap.exists) {
      const data = cacheSnap.data();
      if (Array.isArray(data?.english_reviews)) {
        englishReviews = data.english_reviews
          .filter((r: unknown) => typeof r === "string" && isReviewSensibleAndValid(r as string, context));
      } else if (Array.isArray(data?.reviews)) {
        englishReviews = data.reviews
          .filter((r: unknown) => typeof r === "string" && isReviewSensibleAndValid(r as string, context));
      }
      if (Array.isArray(data?.hinglish_reviews)) {
        hinglishReviews = data.hinglish_reviews
          .filter((r: unknown) => typeof r === "string" && isReviewSensibleAndValid(r as string, context));
      }
    }

    // ── CASE A: Cache Miss for Both Languages (0 valid reviews in doc) ────
    if (englishReviews.length === 0 && hinglishReviews.length === 0) {
      logger.info(`Cache miss/stale for ${docId} (${rawKey}) category: ${context.categoryName}. Generating fresh batches...`);
      isFresh = true;
      const [freshEnglish, freshHinglish] = await Promise.all([
        callGroqLlamaReviewBatch(levels, "english", apiKey, businessCategory, businessName),
        callGroqLlamaReviewBatch(levels, "hinglish", apiKey, businessCategory, businessName),
      ]);
      englishReviews = freshEnglish;
      hinglishReviews = freshHinglish;

      // Save both language arrays in the single review_cache document
      cacheRef.set({
        doc_id: docId,
        raw_key: rawKey,
        business_category: businessCategory,
        business_name: businessName,
        domain_type: context.domainType,
        chips: sortedChips,
        english_reviews: freshEnglish,
        hinglish_reviews: freshHinglish,
        reviews: freshEnglish,
        used_count: 0,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      }, {merge: true}).catch((e) => logger.warn(`Error writing new review_cache ${docId}:`, e));
    } else {
      // ── CASE B: Partial Generation (Document exists but needed language array is empty) ──
      const needEngSync = (effectivePref === "english" || effectivePref === "mixed") && englishReviews.length === 0;
      const needHingSync = (effectivePref === "hinglish" || effectivePref === "mixed") && hinglishReviews.length === 0;

      if (needEngSync || needHingSync) {
        logger.info(`Partial cache miss for ${docId}. Generating missing language pool(s)...`);
        const [genEng, genHing] = await Promise.all([
          needEngSync ? callGroqLlamaReviewBatch(levels, "english", apiKey, businessCategory, businessName) : Promise.resolve([]),
          needHingSync ? callGroqLlamaReviewBatch(levels, "hinglish", apiKey, businessCategory, businessName) : Promise.resolve([]),
        ]);

        const updateDoc: Record<string, unknown> = {updated_at: FieldValue.serverTimestamp()};
        if (genEng.length > 0) {
          englishReviews = genEng;
          updateDoc.english_reviews = genEng;
        }
        if (genHing.length > 0) {
          hinglishReviews = genHing;
          updateDoc.hinglish_reviews = genHing;
        }
        cacheRef.set(updateDoc, {merge: true}).catch((e) => logger.warn(`Error updating partial review_cache ${docId}:`, e));
      }

      // ── CASE C: Background Top-Up Check (< 5 remaining in either pool) ────
      const needEngTopUp = (effectivePref === "english" || effectivePref === "mixed") && englishReviews.length > 0 && englishReviews.length < 5;
      const needHingTopUp = (effectivePref === "hinglish" || effectivePref === "mixed") && hinglishReviews.length > 0 && hinglishReviews.length < 5;

      if (needEngTopUp || needHingTopUp) {
        (async () => {
          try {
            logger.info(`Triggering background top-up for ${docId} (eng: ${englishReviews.length}, hing: ${hinglishReviews.length})`);
            const promises: Promise<unknown>[] = [];
            if (needEngTopUp) {
              promises.push(
                callGroqLlamaReviewBatch(levels, "english", apiKey, businessCategory, businessName).then(async (batch) => {
                  if (batch.length > 0) {
                    await cacheRef.update({
                      english_reviews: FieldValue.arrayUnion(...batch),
                      updated_at: FieldValue.serverTimestamp(),
                    });
                  }
                })
              );
            }
            if (needHingTopUp) {
              promises.push(
                callGroqLlamaReviewBatch(levels, "hinglish", apiKey, businessCategory, businessName).then(async (batch) => {
                  if (batch.length > 0) {
                    await cacheRef.update({
                      hinglish_reviews: FieldValue.arrayUnion(...batch),
                      updated_at: FieldValue.serverTimestamp(),
                    });
                  }
                })
              );
            }
            await Promise.all(promises);
            logger.info(`Background top-up completed for ${docId}`);
          } catch (topUpErr) {
            logger.error(`Background top-up failed for ${docId}:`, topUpErr);
          }
        })().catch((err) => {
          logger.debug("Background top-up error ignored", {err});
        });
      }
    }

    // ── 3. Filter and Assemble Served Review Pool based on Business Language Preference ──
    let servedPool: string[] = [];

    if (effectivePref === "english") {
      servedPool = englishReviews.length > 0 ?
        englishReviews :
        generateLocalFallbackReviews(levels, "english", 10, businessCategory, businessName);
    } else if (effectivePref === "hinglish") {
      servedPool = hinglishReviews.length > 0 ?
        hinglishReviews :
        generateLocalFallbackReviews(levels, "hinglish", 10, businessCategory, businessName);
    } else {
      // Mixed Preference: Interleave English and Hinglish reviews for rich variety
      const mixed: string[] = [];
      const maxLen = Math.max(englishReviews.length, hinglishReviews.length);
      for (let i = 0; i < maxLen; i++) {
        if (i < englishReviews.length) mixed.push(englishReviews[i]);
        if (i < hinglishReviews.length) mixed.push(hinglishReviews[i]);
      }
      servedPool = mixed.length > 0 ?
        mixed :
        [
          ...generateLocalFallbackReviews(levels, "english", 5, businessCategory, businessName),
          ...generateLocalFallbackReviews(levels, "hinglish", 5, businessCategory, businessName),
        ];
    }

    // Pick chosen review (avoiding excludeCurrent if alternatives exist)
    let pickedIndex = 0;
    if (excludeCurrent && servedPool.length > 1) {
      const altIdx = servedPool.findIndex((r) => r.trim() !== excludeCurrent.trim());
      if (altIdx !== -1) pickedIndex = altIdx;
    }

    const servedReview = servedPool[pickedIndex] || servedPool[0];

    return {
      review: servedReview,
      allReviews: servedPool,
      englishReviews,
      hinglishReviews,
      language: effectivePref,
      docId,
      source: isFresh ? "generated_fresh" : "cache",
      remainingCount: servedPool.length,
    };
  } catch (err) {
    logger.error(`Error in getOrServeReview for docId ${docId}:`, err);
    let fallbackPool: string[] = [];
    if (effectivePref === "english") {
      fallbackPool = generateLocalFallbackReviews(levels, "english", 10, businessCategory, businessName);
    } else if (effectivePref === "hinglish") {
      fallbackPool = generateLocalFallbackReviews(levels, "hinglish", 10, businessCategory, businessName);
    } else {
      fallbackPool = [
        ...generateLocalFallbackReviews(levels, "english", 5, businessCategory, businessName),
        ...generateLocalFallbackReviews(levels, "hinglish", 5, businessCategory, businessName),
      ];
    }
    return {
      review: fallbackPool[0],
      allReviews: fallbackPool,
      language: effectivePref,
      docId,
      source: "fallback",
      remainingCount: fallbackPool.length,
    };
  }
}

// ─── Cloud Functions Endpoints ───────────────────────────────────────────────

/**
 * HTTPS CORS Endpoint: fetchReviewForCustomer
 * Invoked by public/r/index.html.
 */
export const fetchReviewForCustomer = onRequest(
  {
    cors: true,
    region: "asia-south1",
    secrets: [groqApiKey],
  },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const body = req.body || {};
      const chips: string[] = Array.isArray(body.chips) ? body.chips : [];
      const step1: string[] = Array.isArray(body.step1) ? body.step1 : [];
      const step2: string[] = Array.isArray(body.step2) ? body.step2 : [];
      const step3: string[] = Array.isArray(body.step3) ? body.step3 : [];
      const businessId: string | undefined = body.businessId;
      const businessName: string | undefined = body.businessName;
      const businessCategory: string | undefined = body.businessCategory || body.archetype;
      const archetype: string | undefined = body.archetype;
      const languagePref: "english" | "hinglish" | "mixed" | undefined = body.languagePref;
      const excludeCurrent: string | undefined = body.excludeCurrent;

      const apiKey = groqApiKey.value();

      const result = await getOrServeReview({
        chips,
        step1,
        step2,
        step3,
        businessId,
        businessName,
        businessCategory,
        archetype,
        languagePref,
        excludeCurrent,
        apiKey,
      });

      res.status(200).json({
        success: true,
        ...result,
      });
    } catch (err) {
      logger.error("Error in fetchReviewForCustomer:", err);
      res.status(500).json({
        success: false,
        error: "Failed to generate review",
      });
    }
  }
);

/**
 * HTTPS CORS Endpoint: consumeReviewOnPost
 * Removes a review from the cache only when the customer taps "Copy & Post to Google".
 */
export const consumeReviewOnPost = onRequest(
  {
    cors: true,
    region: "asia-south1",
  },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const {docId, reviewText} = req.body || {};
      if (docId && reviewText && typeof reviewText === "string") {
        const trimmed = reviewText.trim();
        const db = getFirestore();
        const cacheRef = db.collection("review_cache").doc(docId);
        await cacheRef.update({
          english_reviews: FieldValue.arrayRemove(trimmed),
          hinglish_reviews: FieldValue.arrayRemove(trimmed),
          reviews: FieldValue.arrayRemove(trimmed),
          used_count: FieldValue.increment(1),
          updated_at: FieldValue.serverTimestamp(),
        });
        logger.info(`Consumed review from cache ${docId}`);
      }
      res.status(200).json({success: true});
    } catch (err) {
      logger.warn("Idempotent ignore on consumeReviewOnPost error:", err);
      res.status(200).json({success: true});
    }
  }
);

/**
 * Callable Function: generateReview
 */
export const generateReview = onCall(
  {
    region: "asia-south1",
    secrets: [groqApiKey],
  },
  async (request) => {
    const {
      chips,
      step1,
      step2,
      step3,
      businessId,
      businessName,
      businessCategory,
      archetype,
      languagePref,
      excludeCurrent,
    } = request.data || {};
    const apiKey = groqApiKey.value();

    return await getOrServeReview({
      chips,
      step1,
      step2,
      step3,
      businessId,
      businessName,
      businessCategory,
      archetype,
      languagePref,
      excludeCurrent,
      apiKey,
    });
  }
);
