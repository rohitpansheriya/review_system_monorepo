# 00 — Architecture & Data Schema (Master Reference)

Read this file first, before starting any other task doc. Every other document in this set refers back to the roles, schema, and rules defined here — don't duplicate or redefine them elsewhere.

## Tech Stack
- **Admin/Employee/Owner Panel:** Flutter Web
- **Database:** Firestore (Firebase)
- **Backend logic:** Cloud Functions (Firebase)
- **File storage:** Firebase Storage (logos, QR images)
- **Hosting:** Firebase Hosting
- **Customer-facing review page:** HTML/CSS/JS (lightweight, mobile-first, no heavy framework — loads instantly on a QR scan)
- **Payments:** Razorpay (Individual/Proprietor KYC, Subscriptions API for recurring ₹999/year)
- **Place lookup:** Google Places API (Find Place / Text Search)
- **No AI/LLM dependency** — review text comes from a self-maintained phrase pool (see `07-review-template-system.md`), not generated at runtime.

## User Roles
| Role | Access |
|---|---|
| **Super Admin** | Full control: all businesses, employees, templates, billing, system config |
| **Employee** | Enroll new businesses; view/track only their own enrollments |
| **Business Owner** | Their own business/branch(es): dashboard, category management, star-routing config |
| **Customer** | No login — public QR-scan review flow only |

Implemented via **Firebase Auth custom claims** (`role: admin | employee | owner`). Enforce role checks in **Firestore Security Rules**, not just hidden UI elements — never trust the client alone.

## Scalability Rules (apply these from day one — non-negotiable, avoids future rewrites)
1. **No global real-time counters.** Never increment a single shared document on every scan (hot-document write contention). Log to per-branch/per-scan documents, aggregate on a schedule.
2. **Dashboards read pre-aggregated summaries**, never raw logs. A nightly/hourly Cloud Function rolls up `scan_logs` into `branches/{id}.stats_summary`.
3. **Use Firestore `count()` aggregation queries** for admin platform-wide stats, not manual counting.
4. **Cache business/category config client-side** after first load on the customer review page — don't re-fetch on every interaction within one session.
5. **Category templates are decoupled from businesses** — adding a new business type is a new template document, never a schema change.

## Full Data Model

```
employees (collection)
  └─ employee_id
       - name, contact, role: "employee" | "admin"
       - total_enrollments, this_month_enrollments
       - active: true/false

businesses (collection)
  └─ business_id
       - brand_name, logo_url, category_type
       - default_category_template_id
       - enrolled_by: employee_id
       - enrolled_by_original: employee_id   (kept even after offboarding reassignment)
       - currently_managed_by: employee_id | "admin"
       - subscription_status: "active" | "grace_period" | "deleted"
       - renewal_date, grace_period_ends
       - owner_auth_uid

     branches (subcollection)
       └─ branch_id
            - branch_name, address, whatsapp_number, place_id
            - google_review_link
            - star_routing_config: {1: "thankyou", 2: "whatsapp", 3: "whatsapp", 4: "google", 5: "google"}
            - category_override_id (optional)
            - qr_code_id / nfc_tag_id
            - stats_summary: { total_scans, star_counts, monthly_google_reviews }

category_templates (collection)
  └─ template_id — reusable per business type (Ice Cream, Salon, Restaurant, etc.)
       - categories: [ { name, phrase_pool: [variant1, variant2, ...30+] }, ... ]
       (English only — no per-language translation fields)

scan_logs (collection — write-only per scan, never read directly on dashboard load)
  └─ log_id
       - branch_id, star_rating, timestamp, session_token
       - action_taken: "whatsapp_sent" | "google_review_posted" | "thankyou_only"

commission_records (collection)
  └─ record_id
       - employee_id, business_id
       - amount, payment_mode: "online" | "cash"
       - status: "pending" | "verified" | "paid"
       - date_claimed, date_verified
```

## Cost Reference (for context, not for engineering decisions)
| Scale | Cloud infra/year (no AI cost) |
|---|---|
| 500 clients | ~₹18,000–33,000 |
| 1,000 clients | ~₹32,000–57,000 |
| 10,000 clients | ~₹2,20,000–4,40,000 |

## Task Doc Index
- `01-customer-review-flow.md`
- `02-business-owner-dashboard.md`
- `03-employee-enrollment-panel.md`
- `04-admin-panel.md`
- `05-payment-subscription-renewal.md`
- `06-commission-tracking.md`
- `07-review-template-system.md`
- `08-notifications-system.md`
- `09-qr-nfc-and-place-id.md`
- `10-growth-plan.md` (business, not technical — no build required)
