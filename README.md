# Review System — Monorepo

> **Read [`docs/00-architecture-and-schema.md`](docs/00-architecture-and-schema.md) before anything else.**
> Every other document in this repository refers back to the roles, schema, and rules defined there.

---

## What This Is

A full-stack review-facilitation SaaS for small Indian businesses. Customers scan a QR code, tap category chips assembled from a curated phrase pool, and are routed to WhatsApp or Google Reviews based on their star rating. The system is built for 500–10 000+ business clients with no AI/LLM runtime dependency.

**Tech Stack at a glance**

| Layer | Technology |
|---|---|
| Admin / Employee / Owner panels | Flutter Web |
| Customer review page | Plain HTML + CSS + JS (mobile-first, no framework) |
| Database | Firestore (Firebase) |
| Backend logic | Cloud Functions (Node.js) |
| File storage | Firebase Storage |
| Hosting | Firebase Hosting |
| Payments | Razorpay (Subscriptions API) |
| Place lookup | Google Places API |

---

## Folder Structure

```
review_system_monorepo/
│
├── docs/                          # All product/technical specification documents
│   ├── 00-architecture-and-schema.md   ← START HERE
│   ├── 01-customer-review-flow.md
│   ├── 02-owner-dashboard.md
│   ├── 03-employee-panel.md
│   ├── 04-admin-panel.md
│   ├── 05-payment-subscription-renewal.md
│   ├── 06-commission-tracking.md
│   ├── 07-review-template-system.md
│   ├── 08-notifications-system.md
│   └── 09-qr-nfc-and-place-id.md
│
├── review_page/                   # Customer-facing QR-scan review page (HTML/CSS/JS)
│
├── admin_panel/                   # Flutter Web app — Super Admin & Employee panels
│
├── functions/                     # Firebase Cloud Functions (Node.js / TypeScript)
│
├── firestore/
│   ├── firestore.rules            # Firestore Security Rules (three-role model)
│   ├── firestore.indexes.json     # Composite index definitions
│   └── seed/
│       └── category-templates.json   # Sample category template data (Ice Cream)
│
├── storage/                       # Firebase Storage rules (placeholder)
│
└── hosting/                       # Firebase Hosting config (placeholder)
```

---

## User Roles (Summary)

| Role | Firestore claim | Access |
|---|---|---|
| **Super Admin** | `role: "admin"` | Full control — all businesses, employees, templates, billing |
| **Employee** | `role: "employee"` | Own enrollments only; read businesses they enrolled/manage |
| **Business Owner** | `role: "owner"` | Own business/branches only; no employee or billing data |
| **Customer** | *(unauthenticated)* | Public review page and scan_logs (write-only) |

Roles are enforced in **Firestore Security Rules** — never rely on hidden UI alone.

---

## Key Scalability Rules

From [`docs/00-architecture-and-schema.md`](docs/00-architecture-and-schema.md) — these apply from day one:

1. **No global real-time counters** — write per-scan documents, aggregate on a schedule.
2. **Dashboards read pre-aggregated `stats_summary`** — never raw `scan_logs` on load.
3. **Use Firestore `count()` aggregation** for platform-wide admin stats.
4. **Cache business/category config client-side** for the duration of one review session.
5. **Category templates are decoupled** — new business type = new template document, not a schema change.

---

## Task Doc Index

| Doc | Topic |
|---|---|
| [`00`](docs/00-architecture-and-schema.md) | Architecture & Data Schema (master reference) |
| [`01`](docs/01-customer-review-flow.md) | Customer review flow (QR scan → copy/post) |
| [`02`](docs/02-owner-dashboard.md) | Business owner dashboard |
| [`03`](docs/03-employee-panel.md) | Employee enrollment panel |
| [`04`](docs/04-admin-panel.md) | Admin panel |
| [`05`](docs/05-payment-subscription-renewal.md) | Payment & subscription renewal |
| [`06`](docs/06-commission-tracking.md) | Commission tracking |
| [`07`](docs/07-review-template-system.md) | Review template system (no AI) |
| [`08`](docs/08-notifications-system.md) | Notifications system |
| [`09`](docs/09-qr-nfc-and-place-id.md) | QR / NFC & Place ID |

---

## Before You Can Run Anything

The following external accounts/credentials are **not yet set up** and will be required before any deployment step:

| What | Why |
|---|---|
| **Firebase project** | Needed for `firebase login`, `firebase init`, Firestore, Hosting, Functions, Storage |
| **Google Cloud project** (linked to Firebase) | Google Places API key for branch address lookup |
| **Razorpay account** (Individual/Proprietor KYC) | Subscriptions API for ₹999/year billing |
| **Custom domain** | Firebase Hosting custom domain mapping |
| **Firebase custom claims setup** | A Cloud Function or Admin SDK script to assign `role` claims on user creation |

> **Do not run `firebase login` or `firebase init` until a real Firebase project exists.**
> All local files here are structured to be deployed — but nothing in this repo hard-codes fake credentials.

---

## Development Workflow (once Firebase project exists)

```bash
# 1. Install Firebase CLI globally (once)
npm install -g firebase-tools

# 2. Login
firebase login

# 3. Select your project
firebase use <your-project-id>

# 4. Deploy security rules
firebase deploy --only firestore:rules

# 5. Deploy indexes
firebase deploy --only firestore:indexes

# 6. Deploy functions
cd functions && npm install
firebase deploy --only functions
```

---

## 🔒 Secret Management & Security Guidelines

1. **Zero Hardcoded Secrets**:
   - Production secrets (`RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `BREVO_API_KEY`, `PLACE_API_KEY`) are managed strictly through **Google Cloud Secret Manager** via Firebase Functions (`defineSecret()`).
   - Plain configuration parameters (`REVIEW_DOMAIN`, `RAZORPAY_PLAN_ID`, `BREVO_SENDER_EMAIL`) are managed via `defineString()`.
2. **Client-Side vs Server-Side Separation**:
   - Only public-safe credentials (Firebase Web Client Config) are exposed to browsers via `window.__FIREBASE_CONFIG__`.
   - Razorpay Key Secrets, Service Account private keys, and Brevo API keys are strictly forbidden from appearing in client-side bundles.
3. **Git History & Rotation Policy**:
   - `.env`, `.env.local`, `serviceAccountKey.json`, and `*firebase-adminsdk*.json` are permanently `.gitignore`d.
   - ⚠️ **Mandatory Secret Rotation**: If any real production API key, secret, or service account credential was ever committed or shared outside Secret Manager, rotate it immediately in the respective vendor dashboard (Razorpay, Brevo, Google Cloud Console).

