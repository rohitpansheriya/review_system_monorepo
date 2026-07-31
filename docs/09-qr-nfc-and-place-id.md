# 09 — QR/NFC Generation & Place ID Lookup

**Depends on:** `00-architecture-and-schema.md`, `01-customer-review-flow.md`, `03-employee-enrollment-panel.md`

## QR/NFC Generation
- Triggered on business/branch enrollment (`03`).
- QR encodes: `yourdomain.com/r/{branch_id}` — the branch ID in the URL, not a subdomain per business (Firebase Hosting's custom-domain/subdomain limits make per-business subdomains impractical anyway, and it's unnecessary — one page serves all businesses by ID).
- NFC tag is programmed with the same URL.
- Design: business logo printed on top of the QR, surrounding artwork themed to the business category (e.g. ice-cream-themed border for an ice cream shop), sized for a 4×6 inch acrylic standee.
- Store `qr_code_id` / `nfc_tag_id` reference on the `branches/{id}` document (see `00` schema) — actual image asset goes to Firebase Storage.

## Place ID — Auto-Fetch with Manual Fallback
1. During enrollment (`03`), employee/admin types the business name + city.
2. Call Google Places API "Find Place from Text" (or Text Search) → returns 2-3 candidate matches (name, address, thumbnail).
3. Employee/admin confirms the correct match → Place ID, address, and coordinates auto-fill into the enrollment form.
4. **Fallback:** "Can't find your business? Enter details manually" reveals plain text fields for address and Place ID — for brand-new or unlisted businesses.

## Where Place ID Is Used Downstream
- Customer review flow (`01`): builds the `https://search.google.com/local/writereview/mobile?placeid=...` deep link.
- Phase 2 reply-to-reviews feature (`02`): Google Business Profile API calls are keyed by location/place identifiers.
