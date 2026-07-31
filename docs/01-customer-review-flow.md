# 01 — Customer Review Flow

**Depends on:** `00-architecture-and-schema.md` (schema, scalability rules), `07-review-template-system.md` (phrase pools), `09-qr-nfc-and-place-id.md` (how the branch is identified from the scan)

**Build as:** standalone HTML/CSS/JS page (not Flutter) — must load instantly on a QR scan, mobile-first, no login.

## Entry Point
- QR/NFC encodes a URL like `yourdomain.com/r/{branch_id}` — **not** a subdomain per business (see `00` schema; one page, ID in the URL).
- On load: fetch `branches/{branch_id}` + parent `businesses/{business_id}` (business name, logo, category_template_id) — cache client-side for the rest of the session, don't re-fetch.
- Generate a **session token** for this scan (used later to enforce one-submission-per-scan).

## Screen 1: Landing
- Business logo + name at top.
- Short thank-you/visiting message (e.g. "Thanks for visiting! How was your experience?").
- 5-star selector (tap to rate).

## Screen 2A: Low Rating Path (1-3 stars — thresholds are per-branch, from `star_routing_config`)
- If mapped to `"thankyou"`: show a simple thank-you message, end of flow.
- If mapped to `"whatsapp"`:
  - Show a "Sorry to hear that" message + open text box for feedback.
  - "Send" button constructs a `wa.me/{owner_whatsapp_number}?text={encoded_feedback}` link and opens it — this is a customer-initiated WhatsApp chat, free, no Business API needed.

## Screen 2B: High Rating Path (4-5 stars, mapped to `"google"`)
- Show category chips (multi-select), sourced from `category_templates/{template_id}.categories` (respecting `category_override_id` on the branch if set) and the customer's selected language (see `07`).
- Selecting categories pulls one random phrase variant per selected category from the pool and combines them into an editable text box.
- Deselecting a category removes its phrase from the combined text.
- Language selector visible on this screen (Section below).
- Small-print Terms of Service text visible near this step (exact text in `07-review-template-system.md`).

## Screen 3: Copy & Post
- "Copy & Open Google Maps" button:
  1. Copies the current (possibly edited) review text to clipboard.
  2. Opens `https://search.google.com/local/writereview/mobile?placeid={branch.place_id}` on mobile (falls back gracefully to the standard `writereview` URL on desktop or if the mobile path fails) — this hands off to the native Google Maps app if installed, so the customer's already-logged-in account handles posting without any browser login.
- Customer pastes and posts on their own device — no data is submitted back to your system at this step (you don't get to programmatically verify the post happened; the customer completing this is outside your system's control).

## Language Selection
- Dropdown at top of Screen 2B: e.g. English / Hindi / Gujarati (expandable).
- UI strings stored as translation JSON per language.
- Category labels + phrase pool variants stored per language in the template (see `07`).

## Anti-Abuse
- One `session_token` = one submission. Once a star rating + action (WhatsApp send or Google copy-open) is logged, subsequent attempts on the same session are blocked or redirected to a generic "thank you, already submitted" screen.

## Post-Expiry State
- If `businesses/{id}.subscription_status == "deleted"` or the branch is past grace period: show a simple "This page is temporarily unavailable" screen instead of the review flow — check this status on page load before rendering Screen 1.

## Data Written Per Scan (see `00` schema — `scan_logs`)
- One `scan_logs` document per scan: `branch_id`, `star_rating`, `timestamp`, `session_token`, `action_taken`.
- **Do not** increment any shared/global counter directly — this write is aggregated later by a scheduled Cloud Function (see `00`, Scalability Rule #1-2).
