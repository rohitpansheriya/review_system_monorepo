# 02 — Business Owner Dashboard

**Reads first:** `00-overview-and-architecture.md` for schema and rules.
**Built with:** Flutter Web, role = `owner`. Auth via Firebase Auth (`owner_auth_uid` on the business doc).

## Access model
An owner can only read/write documents where `businesses/{business_id}.owner_auth_uid == request.auth.uid` (enforce in Firestore Security Rules). If the business has multiple branches, the owner sees all branches under their one business doc.

## Screens

### 1. Login
- Provisioned at enrollment time — owner sets their password via a magic link sent by the enrolling employee/admin (see `03-employee-panel.md` / `04-admin-panel.md` for provisioning).

### 2. Dashboard Home
- If single branch: shows that branch's `stats_summary` — total scans, star-rating distribution, monthly count of reviews sent to Google.
- If multi-branch: a **branch switcher** dropdown at top, plus an **aggregated "all branches"** view (sum of all branches' `stats_summary` fields — computed via a Cloud Function, not live-summed on every dashboard load).
- No complaint-keyword analysis — deliberately out of scope.

### 3. Category Management
- View the business's assigned category template.
- Owner can toggle which categories are active for their business (cannot edit the phrase pool itself — that's admin-only, see `04-admin-panel.md`).
- Editing category selection is part of what the ₹999/year renewal keeps active — if `subscription_status` is expired/grace period, show this screen as read-only with a "renew to edit" prompt.

### 4. Star-Routing Config
- Editable table: for each star (1-5), a dropdown to select "Thank-you only" / "WhatsApp" / "Google review".
- This was originally set at enrollment (see `03-employee-panel.md`) but the owner can change it anytime here without needing the employee/admin involved.
- Writes to `branches/{branch_id}.star_routing_config`.

### 5. Renewal / Payment
- Shows current `renewal_date`, `subscription_status`, and (if applicable) `grace_period_ends`.
- "Pay ₹999 to renew" button → Razorpay checkout (see `06-payments-and-commission.md` for the exact integration).
- Banner + past-due state styling if in grace period, per `05-backend-jobs-integrations.md`'s status transition logic.

### 6. (Phase 2 — build after MVP) Reply to Google Reviews
- Requires the business's Google Business Profile to be verified, and the owner to complete a Google OAuth connect flow (`business.manage` scope) from this screen.
- Only enable this screen once your own platform's Google Business Profile API access has been approved (this can take time — apply early, see `05-backend-jobs-integrations.md`).
- Not part of MVP — build this after core flows are live and stable.

## Edge cases to handle
- Owner tries to access a branch that isn't theirs (e.g. manipulated URL) → deny at the Security Rules layer, not just hide the UI element.
- Business in `"deleted"` status → owner should see a clear "Your subscription has lapsed and data was removed — contact us to re-enroll" screen instead of a broken dashboard.
- Owner changes star-routing config mid-day → takes effect immediately for all subsequent scans (no caching delay beyond the review page's normal per-session config fetch).
