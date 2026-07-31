# 03 — Employee Panel

**Reads first:** `00-overview-and-architecture.md` for schema and rules.
**Built with:** Flutter Web, role = `employee`. Same codebase/app as admin panel, but a restricted view based on the `employee` custom claim.

## Access model
An employee can only read/write `businesses` documents where `enrolled_by == employee_id` (their own). They cannot see or edit other employees' enrolled businesses, cannot access billing/subscription overrides, and cannot edit category templates or phrase pools (admin-only).

## Screens

### 1. Login
- Credentials created by admin (see `04-admin-panel.md`).

### 2. Enroll New Business
Form fields:
- Business name
- Category template selection (from the existing master library)
- Branch details: branch name, address, WhatsApp number
- Owner contact info (name, phone, **email** — required for free renewal notifications)
- Logo upload
- **Place ID:** auto-fetch by typing business name + city (Places API "Find Place" search) → shows 2-3 candidate matches (name, address, thumbnail) → employee confirms the right one → Place ID, address, coordinates auto-fill. If no match found: "Can't find your business? Enter details manually" reveals plain text fields for address and Place ID.
- **Star-routing config (required, not defaulted):** a row for stars 1-5, each with a dropdown ("Thank-you only" / "WhatsApp" / "Google review"). The employee asks the business owner directly on the spot and sets this — it's core to how the feedback loop behaves, so it must be an explicit choice, never left at a silent default.

On submit:
- Creates the `businesses` document (`enrolled_by`, `enrolled_by_original` both set to this employee's ID), a first `branches` subdocument, sets `renewal_date = today + 1 year`, `status: "active"`.
- Triggers QR/NFC code generation (see `05-backend-jobs-integrations.md`).
- Provisions the owner's Firebase Auth account and sends a magic-link email so they can set their own password.
- Increments this employee's `total_enrollments` and `this_month_enrollments` counters (`employees/{employee_id}`).

### 3. My Enrolled Businesses
- List of all businesses where `enrolled_by == this employee_id`.
- Shows renewal status per business (active / renewal due soon / grace period).
- Read-only list — employee cannot edit these businesses' details post-enrollment (that's the owner's job via `02-owner-dashboard.md`, or admin's via `04-admin-panel.md`).

### 4. My Enrollment & Commission Tracker
- Total enrolled (all-time), this month's count.
- List of `commission_records` where `employee_id == this employee`, showing status (`pending` / `verified` / `paid`) per record — see `06-payments-and-commission.md` for the full commission workflow, including the cash-payment claim process this screen needs to support (a "Log Cash Payment Collected" action tied to a specific business).

## Edge cases to handle
- Employee tries to re-enroll a business that already exists (duplicate Place ID) → warn and block, don't create a duplicate business record.
- Employee account deactivated mid-session → all their in-progress form state should be discarded; further requests should fail auth checks immediately.
- Employee offboarding: when admin deactivates an employee (`04-admin-panel.md`), all businesses with `enrolled_by == that employee` get `currently_managed_by` set to `"admin"` — no other employee inherits them. `enrolled_by_original` is preserved as an audit trail and is never overwritten.
