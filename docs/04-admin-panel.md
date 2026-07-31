# 04 — Admin Panel

**Depends on:** `00-architecture-and-schema.md`, `03-employee-enrollment-panel.md`, `06-commission-tracking.md`, `07-review-template-system.md`

**Build as:** the full-access role view within the Flutter Web panel (role: `admin`).

## Enroll Business Directly
- Same form as `03-employee-enrollment-panel.md`, no restrictions — `enrolled_by` and `currently_managed_by` both set to `"admin"` (or the admin's own ID if you want per-admin tracking too).

## Employee Management
- Create/deactivate employee profiles.
- View each employee's: total enrollments, this-month enrollments, list of their businesses with renewal status, commission summary (pending/verified/paid).
- **Offboarding action:** deactivating an employee triggers a Cloud Function that bulk-updates all their `businesses` documents — sets `currently_managed_by: "admin"`, keeps `enrolled_by_original` intact. No reassignment UI to another employee is needed, since that's explicitly not the design (see `00`).

## Category Template Library
- Master list of templates (Ice Cream, Salon, Restaurant, etc.).
- Full CRUD on each template's categories and their phrase pools (30+ variants each — see `07-review-template-system.md`), including per-language variants (Section in `07`).
- Assign a template to a business at enrollment, or change it later.
- Allow branch-level `category_override_id` for businesses needing custom categories outside the standard templates.

## Platform-Wide Stats
- Total businesses, total scans, renewals due (grouped by window: 30/15/7/1 days), revenue snapshot.
- Use Firestore `count()` aggregation queries here, not manual iteration over documents (see `00` Scalability Rule #3).

## Subscription/Renewal Overrides
- Manually extend a grace period or reactivate a deleted business record if needed (edge-case handling, e.g. payment dispute).

## Commission Verification Queue
- List of `commission_records` with `payment_mode: "cash"` and `status: "pending"` (full verification flow in `06`).
- Admin confirms cash was physically received before approving.

## What Admin Does NOT Need a Screen For
- Reassigning an offboarded employee's businesses to another employee — explicitly not part of the design; it's an automatic bulk update to `"admin"` only.
