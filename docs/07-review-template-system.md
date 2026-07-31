# 07 — Review Template System (No AI)

**Depends on:** `00-architecture-and-schema.md`, `01-customer-review-flow.md`, `04-admin-panel.md`

**Important:** review text is **not** AI-generated. It's assembled from a self-maintained pool of pre-written phrases that admin controls directly. No LLM API call, no ongoing AI cost, no dependency on an external AI service for this feature.

## Schema (within `category_templates`, see `00`)
```
category_templates (collection)
  └─ template_id
       - categories: [
           {
             name: "Taste",
             phrase_pool: [variant1, variant2, ..., variant30+],
             translations: { hi: [...30+], gu: [...30+] }
           },
           ... (6-7 categories per template)
         ]
```

## How Assembly Works (Customer-Facing, see `01`)
1. Customer selects one or more category chips.
2. For each selected category, the system picks **one phrase variant at random** from that category's pool (in the customer's selected language).
3. Selected phrases are combined into the editable review text box.
4. Deselecting a category removes its phrase; reselecting picks a new random variant (not necessarily the same one as before).
5. Customer can freely edit the combined text before copying/posting.

## Admin's Job (Ongoing, via `04-admin-panel.md`)
- Maintain **30+ phrase variants per category**, per template, per business type.
- Add, edit, or retire phrases anytime — no code deployment needed, this is pure data editing in Firestore via the admin panel UI.
- Maintain translated variants for each supported language (Section below).

## Why 30+ Variants Is Enough
With 3 categories selected out of 6-7 typical, and 30 variants each: 30 × 30 × 30 = 27,000 possible combinations for one selection pattern alone — across all selection patterns customers might choose, total unique output text is in the hundreds of thousands. This comfortably avoids repetition even at 10,000-client, 50-scans/day scale.

## Duplicate-Content Risk — Build This In From the Start
If many different businesses of the same category type (e.g. 50 ice cream shops) draw from the identical pool, two different customers at two different businesses could post identical sentences on two different Google listings — a pattern Google's spam detection can flag.

**Mitigation (build into the template system, not an afterthought):**
- Maintain 2-3 slightly different **versions of each category's pool**, and assign different businesses of the same type to different pool versions.
- Prefer larger pools (30+, as already decided) over smaller ones.

## Multi-Language Support
- Language selector on the customer review page (English / Hindi / Gujarati, expandable).
- UI strings: translation JSON per language.
- Category labels + phrase pool variants: stored as a translation map per category (see schema above) — translate once per template, reused across every business using that template.

## Terms of Service (Review Integrity Policy)
Shown as permanent small-print on the review page, near the category-select step — not a one-time popup:

> - Suggested phrases are provided only as a starting point — they don't replace the customer's own words.
> - The customer is free to edit the review before posting it.
> - The customer should only describe their own genuine experience.
> - Fake or false reviews must not be posted.
> - The customer has complete freedom to give any rating, regardless of the review content.

This is your documented defense if Google or a customer ever questions review authenticity, and it reinforces the customer-edits-before-posting design already built into the flow (`01`).

## Optional Future Enhancement (Not for Initial Build)
A light AI paraphrasing pass over the *combined, already-customer-approved* text, purely to smooth phrasing into a single natural paragraph — not to generate content from scratch, and not aimed at disguising that phrases originated from a template. If added later, keep it as an optional "smooth this out" button after the customer has already reviewed the combined text, not a replacement for the phrase-pool step itself.
