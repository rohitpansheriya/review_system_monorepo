# 📋 PROJECT OVERVIEW — Review System Platform

> **Last updated**: August 2026
> This document explains the complete project, every user role, every workflow step, and how all pieces connect. Read this first if you're new to the project.

---

## 🎯 What Is This?

A **SaaS platform** that helps local businesses (restaurants, salons, cafes, etc.) get more **positive Google reviews** from their customers — automatically.

**How it works in 30 seconds:**
1. Our **field employee** visits a local business and enrolls them.
2. We create a **QR code standee** for the business counter.
3. When a customer scans the QR code, they see a beautiful review page.
4. If they give **4-5 stars** → we assemble a ready-made review text and redirect them to **Google Maps** to paste it.
5. If they give **1-3 stars** → we route them to **private WhatsApp feedback** (so the negative review never goes public).

**Business model**: ₹999/year subscription per business. Employees earn commission per enrollment.

---

## 👥 User Roles

| Role | Who | What They Do |
|------|-----|-------------|
| **Admin** | Platform owner (you) | Manages everything — employees, businesses, templates, subscriptions, commission payouts |
| **Employee** | Field sales person | Visits businesses, enrolls them, collects cash, manages standee delivery |
| **Business Owner** | The enrolled business | Views their dashboard, manages review categories, sees analytics |
| **Customer** | Walk-in customer | Scans QR code → rates → posts review (no login needed) |

All roles use **Firebase Auth** with custom claims (`role: admin | employee | owner`). Customers don't need any login.

---

## 🏗️ Tech Stack

| Component | Technology |
|-----------|-----------|
| Admin / Employee / Owner Panel | **Flutter Web** (single codebase, role-gated) |
| Customer Review Page | **Standalone HTML/CSS/JS** (mobile-first, instant load on QR scan) |
| Database | **Cloud Firestore** (Firebase) |
| Backend Logic | **Cloud Functions** (Firebase, Node.js/TypeScript) |
| File Storage | **Firebase Storage** (logos, QR images, employee KYC docs) |
| Hosting | **Firebase Hosting** (review page + Flutter panel) |
| Payments | **Razorpay** (online) + **Cash collection** (offline) |
| Place Lookup | **Google Places API (New)** — `POST /v1/places:searchText` |
| Review Text | **Phrase pool system** — no AI/LLM, hand-curated phrases per category |

---

## 🔄 COMPLETE WORKFLOW — Step by Step

### Phase 1: Employee Enrolls a Business

```
Employee visits business → Opens Flutter panel → Taps "+ Enroll Business"
```

**What the employee fills in:**

| Field | Description |
|-------|-------------|
| Brand Name | e.g. "Creamy Ice Cream Parlour" |
| Category Type | e.g. "Ice Cream", "Restaurant", "Salon" |
| Logo | Upload business logo (min 500×500px) |
| Owner Name | Business owner's full name |
| Owner Email | This becomes the owner's login email |
| Owner Phone / WhatsApp | For private feedback routing |
| Branch Name | e.g. "Main Branch", "City Center Branch" |
| Branch Address | Physical address |
| **Google Place ID** | ⭐ See "Place ID" section below |
| WhatsApp Monitor Number | Who receives private feedback messages |

**"Same as Owner" shortcut**: When adding branches, click **"Same as Owner"** to copy the owner's phone as the WhatsApp monitor number.

**After submission**: Business is created in Firestore with `subscription_status: "pending_payment"`. No QR code is generated yet.

---

### Phase 2: Google Place ID — How It Works

> **This is critical.** The Place ID is what connects the review page to the business's actual Google Maps listing.

**What is a Place ID?**
A unique identifier Google assigns to every business on Google Maps. Example: `ChIJN1t_tDeuEmsRUsoyG83frY4`

**How to find it:**
1. During enrollment, the employee types the business name + city in the **Google Places search** field.
2. The system calls our Cloud Function → Google Places API (New) → returns matching businesses.
3. Employee selects the correct match → Place ID is auto-filled.
4. If no API key is configured (emulator/dev), **mock candidates** are returned for testing.
5. Employee can also enter the Place ID manually if they know it.

**How we use the Place ID:**
When a customer taps "Post Review on Google" on the review page, we redirect them to:
```
https://search.google.com/local/writereview?placeid={PLACE_ID}
```
This opens **Google Maps directly on the "Write a Review" screen** for that exact business. The customer just pastes the pre-assembled review text and hits Post.

> ⚠️ **Without a valid Place ID, the Google review redirect won't work.** The review page will still function (stars, phrase selection, WhatsApp feedback), but the "Post on Google" button needs a real Place ID.

---

### Phase 3: Payment — Cash Collection Flow

```
Employee collects cash from business owner → Marks as collected → Admin verifies → Business activates
```

**Two payment paths:**

#### Path A: Online Payment (Razorpay)
1. Employee sends payment link to owner.
2. Owner pays ₹999 via Razorpay (card/UPI/netbanking).
3. Razorpay webhook fires → Cloud Function activates the business automatically.
4. QR code is generated.

#### Path B: Cash Collection (Most Common)

| Step | Who | What Happens |
|------|-----|-------------|
| **1. Collect** | **Employee** | Collects ₹999 cash from the business owner at the counter. Taps **"Collect Cash Payment"** on the Payment screen. A `commission_record` is created with `employee_collected: true`, `status: pending`. |
| **2. Confirm** | **Admin** | Logs into Admin Panel → **Commission Queue** tab. Sees the pending record with "Employee Collected ✅" badge. Clicks **"Confirm Cash Received (Admin)"** after the employee deposits the cash. |
| **3. Activate** | **System** | On admin confirmation: commission record status → `verified`, business `subscription_status` → `active`, `renewal_date` → +365 days from now. |
| **4. QR Generated** | **System** | QR code standee image is generated for the branch pointing to `/r/{branch_id}`. |

> **Key rules:**
> - **Employee cannot self-activate** a business. Only Admin confirmation activates it.
> - **Owner is NOT part of the cash confirmation flow.** It's Employee (collects) + Admin (confirms).
> - **For enrollments done by Admin directly**, no employee agreement is required — Admin can confirm immediately.
> - Admin can also **delete** erroneous commission records from the queue.

---

### Phase 4: QR Code Standee & Review Page

```
QR code generated → Printed on acrylic standee → Shipped to business → Customer scans
```

**QR Code points to**: `https://{domain}/r/{branch_id}`

**When a customer scans the QR code, here's what happens:**

1. **Review page loads** (lightweight HTML page, no app download needed).
2. Page fetches business config from Firestore: brand name, logo, category template, star routing config.
3. **Customer taps stars** (1-5).

**Star Routing Logic** (configured per branch):

| Stars | Default Route | What Happens |
|-------|--------------|-------------|
| 1 ⭐ | `thankyou` | Shows a "Thank you" message. No public review. |
| 2 ⭐⭐ | `thankyou` | Shows a "Thank you" message. No public review. |
| 3 ⭐⭐⭐ | `whatsapp` | Opens WhatsApp with pre-filled private feedback to the owner. |
| 4 ⭐⭐⭐⭐ | `google` | Shows category phrase chips → assembles review text → "Copy & Open Google Maps" |
| 5 ⭐⭐⭐⭐⭐ | `google` | Shows category phrase chips → assembles review text → "Copy & Open Google Maps" |

**The "Google" route in detail:**
1. Customer sees category-specific phrase chips (e.g. "Great flavors", "Friendly staff", "Clean place").
2. Customer taps the phrases that apply — text box auto-assembles a natural-sounding review.
3. Customer taps **"Copy & Open Google Maps"** → review text copied to clipboard → browser opens `https://search.google.com/local/writereview?placeid={PLACE_ID}`.
4. Customer pastes the text and posts.

**No AI is used.** All phrase variants come from a hand-curated phrase pool in `category_templates`. Each category (Ice Cream, Restaurant, Salon, etc.) has 30+ phrase variants to ensure reviews look natural and unique.

---

### Phase 5: Owner Dashboard

```
Owner logs in → Sees analytics, manages categories, monitors reviews
```

**Owner login**: The email provided during enrollment becomes the owner's login. Password is set during account provisioning (triggered by Admin or automatically after activation).

**Before cash confirmation**: Owner CAN log in but sees a **"Pending Activation"** banner. They cannot access full features until Admin confirms the cash payment.

**After activation**, the owner dashboard shows:
- **Home**: Scan count, star rating breakdown, review redirects, monthly trends
- **Categories**: Toggle active review categories (e.g. enable/disable "Ambiance" phrases)
- **Star Routing**: Customize which stars route to Google vs WhatsApp vs Thank You
- **Renewal**: View subscription status, pay renewal when due
- **Reply to Reviews**: (Phase 2 — Google Business Profile API integration)

---

### Phase 6: Standee Fulfillment Tracking

```
Employee tracks: Not Ordered → Printed → Shipped → Delivered
```

Each branch has a `standee_status` field:
- `not_ordered` → `printed` → `shipped` → `delivered`

The employee updates this as the physical acrylic standee moves through production and delivery.

---

## 🔧 Admin Panel — Full Capabilities

| Tab | What Admin Can Do |
|-----|------------------|
| **Platform Stats** | Total businesses, revenue, enrollments, commission summaries |
| **Employees** | Create/edit/offboard employees, verify KYC documents, view per-employee stats |
| **All Businesses** | View/edit ALL enrolled businesses, filter by status (Active/Pending/Grace/Deleted), filter by date range, edit business details, override subscriptions |
| **Commission Queue** | Verify employee cash collections, mark commissions as paid (with UTR reference), delete erroneous records |
| **Templates** | Create/edit/delete category templates (phrase pools for review assembly) |

---

## 📊 Data Flow Diagram

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Employee    │────▶│  Enrollment  │────▶│  Draft Business  │
│  (Flutter)   │     │  Form        │     │  (pending_payment)│
└─────────────┘     └──────────────┘     └────────┬────────┘
                                                   │
                    ┌──────────────┐                │
                    │  Cash        │◀───────────────┘
                    │  Collection  │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐     ┌─────────────────┐
                    │  Admin       │────▶│  Active Business │
                    │  Confirms    │     │  + QR Code       │
                    └──────────────┘     └────────┬────────┘
                                                   │
                    ┌──────────────┐                │
                    │  Customer    │◀───────────────┘
                    │  Scans QR    │     (QR → /r/{branch_id})
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ Thank You│ │ WhatsApp │ │ Google   │
        │ (1-2 ⭐) │ │ (3 ⭐)   │ │ Review   │
        └──────────┘ └──────────┘ │ (4-5 ⭐) │
                                   └──────────┘
                                        │
                                        ▼
                              ┌──────────────────┐
                              │ Google Maps       │
                              │ Write Review Page │
                              │ (via Place ID)    │
                              └──────────────────┘
```

---

## 📁 Repository Structure

```
review_system_monorepo/
├── admin_panel/          # Flutter Web app (Admin + Employee + Owner panels)
│   ├── lib/
│   │   ├── core/         # Constants, theme, helpers
│   │   ├── models/       # Data models (Business, Branch, Employee, Commission)
│   │   ├── providers/    # State management (Provider pattern)
│   │   ├── screens/      # UI screens per role (admin/, employee/, owner/, enroll/)
│   │   └── services/     # Firestore, Storage, Places API services
│   └── web/              # Flutter web entry point
├── review_page/          # Customer-facing review page (HTML/CSS/JS)
│   └── index.html        # Single-file review flow (mobile-first)
├── functions/            # Cloud Functions (TypeScript)
│   └── src/
│       ├── placeSearch.ts       # Google Places API proxy
│       ├── commissions.ts       # Cash payment verification functions
│       ├── razorpay.ts          # Online payment webhook handler
│       ├── secrets.ts           # API keys & config registry
│       └── ...
├── firestore.rules       # Firestore security rules
├── firestore/
│   └── firestore.indexes.json  # Composite & collection group indexes
├── scripts/              # Seed scripts, test scripts
├── docs/                 # Architecture & task documents
├── TESTING.md            # Complete testing guide with credentials
└── firebase.json         # Firebase project configuration
```

---

## 🔐 Security Model

| Principle | Implementation |
|-----------|---------------|
| Role-based access | Firebase Auth custom claims (`role: admin/employee/owner`) |
| Server-side enforcement | Firestore Security Rules — never trust client alone |
| Employee isolation | Employees can only read/write businesses they enrolled |
| Owner isolation | Owners can only read/write their own business |
| Admin full access | Admin reads/writes everything |
| No self-activation | Employees cannot set `subscription_status` to `active` |
| Financial audit trail | Commission records cannot be deleted by employees (admin only) |
| API key protection | Google Places API key in Secret Manager, proxied through Cloud Function |

---

## 💰 Commission & Payout Flow

```
Employee collects ₹999 cash
    └──▶ commission_record created (status: pending, employee_collected: true)
            └──▶ Admin confirms cash receipt
                    └──▶ status: verified, business: active
                            └──▶ Admin marks payout (enters UTR reference)
                                    └──▶ status: paid (employee receives their commission cut)
```

**Commission record statuses:**
- `pending` — Employee collected cash, waiting for admin verification
- `verified` — Admin confirmed, business activated
- `paid` — Admin sent commission payout to employee (UTR recorded)
- `disputed` — Something went wrong (admin can delete these)

---

## 🧪 Testing

See **[TESTING.md](TESTING.md)** for the complete testing guide with:
- All login credentials (admin, employee, owner)
- Step-by-step emulator setup
- 18 end-to-end test scenarios
- Troubleshooting guide

---

## 🚀 Deployment Checklist

Before going live, ensure:

- [ ] Firebase project created with Blaze plan
- [ ] `PLACE_API_KEY` set in Secret Manager (Google Places API New enabled)
- [ ] `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` set
- [ ] `BREVO_API_KEY` set (for transactional emails)
- [ ] `BREVO_SENDER_EMAIL` verified in Brevo dashboard
- [ ] Custom domain configured in Firebase Hosting
- [ ] `firebase deploy` run successfully (rules, functions, indexes, hosting)
- [ ] Admin account created with `role: admin` custom claim
- [ ] At least one category template seeded
- [ ] Test QR scan on real iPhone and Android phone
