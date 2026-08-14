# Complete System QA & Testing Guide (`TESTING.md`)

This guide provides step-by-step instructions for running automated and manual verification tests across all roles (`customer`, `employee`, `owner`, `admin`) and system components against the **Firebase Emulator Suite** and live test environments.

---

## 🚀 One-Command Master Automated Execution

To run all automated system tests in sequence against the running emulator:

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/seed-firestore.js && \
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/run-all-tests.js && \
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-owner-dashboard.js && \
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-commission-tracking.js && \
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-admin-panel.js
```

---

## 🛠️ Prerequisites & Setup

### 1. Start Firebase Emulator Suite

```bash
npx firebase emulators:start --only firestore,hosting,auth,functions
```

### 2. Seed Initial Test Data

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/seed-firestore.js
```

---

## 📋 PART B — Numbered Manual Test Guide (Emulator)

---

### T1: Customer Review Page — QR Load & Category Phrase Selection
- **Verifies**: `01-customer-review-flow.md` & `07-review-template-system.md`
- **Commands**:
  ```bash
  # Open customer page in browser
  open http://127.0.0.1:5002/r/test_branch_001
  ```
- **Manual Actions**:
  1. Open `http://127.0.0.1:5002/r/test_branch_001`.
  2. Verify brand name ("Patel Ice Cream & Shakes") and logo render.
  3. Select 5 stars. Select category chip "Flavor Variety".
  4. Verify a randomized phrase variant is appended to the editable review text field.
  5. Deselect the category chip — verify the phrase is removed from the text area.
- **Pass Criteria**: Category chip tap dynamically appends/removes phrases into editable text.

---

### T2: Star Routing Paths (WhatsApp vs Google Maps vs Thank You)
- **Verifies**: `01-customer-review-flow.md` & `00-architecture-and-schema.md`
- **Commands**:
  ```bash
  open http://127.0.0.1:5002/r/test_branch_001
  ```
- **Manual Actions**:
  1. **1-3 Stars (WhatsApp Routing)**: Tap 1 star. Fill feedback text. Click submit.
     - *Expect*: Opens WhatsApp `wa.me/919876543210?text=...` without `+`.
  2. **4-5 Stars (Google Routing)**: Refresh page, tap 5 stars, tap "Copy Review & Open Google".
     - *Expect*: Text is copied to clipboard, and browser opens `https://search.google.com/local/writereview?placeid=ChIJN1t_tDeuEmsRUsoyG83frY4`.
- **Pass Criteria**: Routing follows `star_routing_config` mapped per branch.

---

### T3: Single-Submission Scan Lockout
- **Verifies**: `01-customer-review-flow.md` (duplicate submission prevention)
- **Manual Actions**:
  1. Complete a review submission on `/r/test_branch_001`.
  2. Immediately attempt to click "Submit" again or refresh without re-scanning.
- **Pass Criteria**: UI displays "Thank you! Review already submitted for this scan." preventing double submission.

---

### T4: Unavailable State for Lapsed / Deleted Business
- **Verifies**: `01-customer-review-flow.md` & `05-payment-subscription-renewal.md`
- **Commands**:
  ```bash
  open http://127.0.0.1:5002/r/test_branch_004
  ```
- **Manual Actions**:
  1. Navigate to `/r/test_branch_004` (seeded with `subscription_status: "deleted"`).
- **Pass Criteria**: Customer review page displays "This review page is currently unavailable" banner and disables star selection.

---

### T5: Duplicate Content Mitigation across Branches
- **Verifies**: `07-review-template-system.md` (pool versions `v1`, `v2`, `v3`)
- **Manual Actions**:
  1. Open `/r/test_branch_001` (uses `pool_version: "v1"`). Tap category "Flavor Variety". Note phrase.
  2. Open `/r/test_branch_002` (uses `pool_version: "v2"`). Tap same category.
- **Pass Criteria**: Two branches under the same industry template draw distinct phrase variants.

---

### T6: Business Enrollment (Single & Multi-Branch Modes)
- **Verifies**: `03-employee-panel.md`
- **Commands**:
  ```bash
  # Launch Flutter Web Admin Panel
  cd admin_panel && flutter run -d chrome --web-port 3000
  ```
- **Manual Actions**:
  1. Log in as Employee (`emp.test@example.com` / `password123`).
  2. Click "Enroll New Business". Select "Multi-Branch Mode".
  3. Enter Brand Name, Phone (+91 format), select Category Template.
  4. Add 2 branches, assign star routing for 1–5 stars. Click "Submit Enrollment".
- **Pass Criteria**: Creates `businesses/{id}` doc in `pending_payment` state with atomic branch subdocuments. Zero orphan docs.

---

### T7: Payment Activation & Razorpay Webhook Idempotency
- **Verifies**: `05-payment-subscription-renewal.md`
- **Commands**:
  ```bash
  # Trigger webhook test script
  node functions/src/scripts/testWebhook.ts
  ```
- **Pass Criteria**: Firing `payment.captured` webhook flips business `pending_payment` -> `active`, sets `renewal_date` = +1 year, provisions owner account, and creates exactly ONE `commission_records` entry. Retrying webhook with same payment ID does NOT duplicate commission record.

---

### T8: Abandoned Draft Cleanup (48-Hour Threshold)
- **Verifies**: `05-payment-subscription-renewal.md`
- **Commands**:
  ```bash
  # Run grace & draft cleanup verification
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-grace-and-deletion.js
  ```
- **Pass Criteria**: Drafts in `pending_payment` status created > 48 hours ago are purged. Active/grace/deleted businesses and commission records are NEVER deleted.

---

### T9: Employee Panel — Enrollment Filter & Business Edits
- **Verifies**: `03-employee-panel.md`
- **Manual Actions**:
  1. In Employee Panel, test filter toggle ("Pending Payment" vs "Active / Successful" vs "7 Days").
  2. Select an enrolled business. Edit Brand Name & WhatsApp number. Click Save.
- **Pass Criteria**: Business list filters instantly; edit updates Firestore and local state without requiring page refresh.

---

### T10: Employee Profile & Document Upload Safeguard
- **Verifies**: `03-employee-panel.md`
- **Manual Actions**:
  1. In Employee Panel, navigate to "My Profile".
  2. Admin sets `documents_verified = "verified"`.
  3. Update bank account / UPI details or upload a new KYC document.
- **Pass Criteria**: Any payout or document change automatically resets `documents_verified` back to `"pending"`.

---

### T11: Owner Dashboard — Pre-Aggregated Stats & Multi-Branch Switcher
- **Verifies**: `02-owner-dashboard.md` & Scalability Rule #1/#2
- **Commands**:
  ```bash
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-owner-dashboard.js
  ```
- **Manual Actions**:
  1. Log in as Owner (`owner.test001@example.com`).
  2. View Dashboard Home. Check Total Scans and Google Review conversions.
  3. Toggle branch dropdown between "All Branches (Aggregated)" and individual branches.
- **Pass Criteria**: Multi-branch view sums pre-aggregated `stats_summary` totals without performing raw `scan_logs` queries.

---

### T12: Owner Category Management & Grace Period Read-Only Gating
- **Verifies**: `02-owner-dashboard.md` & `05-payment-subscription-renewal.md`
- **Manual Actions**:
  1. In Owner Dashboard, navigate to "Categories" tab. Toggle a category ON/OFF.
  2. Set business status to `grace_period`. Refresh screen.
- **Pass Criteria**: Active status permits category toggling. Grace period renders screen in READ-ONLY mode with "Renew to edit" prompt banner.

---

### T13: Admin Direct Enrollment & Employee Offboarding
- **Verifies**: `04-admin-panel.md` & `00-architecture-and-schema.md`
- **Commands**:
  ```bash
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-admin-panel.js
  ```
- **Manual Actions**:
  1. Log in as Admin (`admin.test001@example.com`).
  2. Navigate to "Employees" tab. Click "Offboard / Deactivate Employee".
- **Pass Criteria**: Employee `status` becomes `"inactive"`. All managed businesses bulk-update `currently_managed_by = "admin"`, keeping `enrolled_by_original` intact.

---

### T14: Admin Category Template Library CRUD
- **Verifies**: `04-admin-panel.md` & `07-review-template-system.md`
- **Manual Actions**:
  1. In Admin Panel, navigate to "Templates" tab. Select "Restaurant".
  2. Click "Add Phrase Variant" under `v1` pool version. Type `"Sensational culinary experience!"`.
  3. Open customer review page (`/r/test_branch_003`).
- **Pass Criteria**: Customer review page reflects the new phrase variant immediately without code redeployment.

---

### T15: Two-Step Cash Commission Verification & Dispute Gate
- **Verifies**: `06-commission-tracking.md`
- **Commands**:
  ```bash
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-commission-tracking.js
  ```
- **Manual Actions**:
  1. Employee logs cash payment -> status `pending`.
  2. Admin confirms cash receipt in Commission Queue -> status remains `pending`.
  3. Owner clicks "Yes, I Paid" in Owner Dashboard -> status flips to `verified`.
  4. If Owner clicks "No, I Did Not Pay" -> status flips to `disputed` (not verified, not deleted).
- **Pass Criteria**: Commission flips to `verified` ONLY when BOTH confirmations are set.

---

### T16: Platform-Wide Stats (`count()` Aggregations)
- **Verifies**: `04-admin-panel.md` & Scalability Rule #3
- **Manual Actions**:
  1. In Admin Panel, navigate to "Stats" tab.
  2. Observe Total Businesses, Active, Grace, and Draft counts.
- **Pass Criteria**: Stats use Firestore `count()` queries; pending payment drafts are excluded from paying business counts.

---

## 📱 PART C — Real-Service / Device Testing (Live / Staging)

> **Note**: These tests require live or test-mode third-party API credentials, real push/email tokens, or a physical mobile device.

### C1: Real Razorpay Test-Mode Payment Checkout & Webhook
- **Verifies**: End-to-end Razorpay checkout modal & live webhook signature verification.
- **Prerequisites**: Razorpay Test Key ID & Secret configured in backend secrets.
- **Test Card Details**:
  - **Card Number**: `4111 1111 1111 1111`
  - **Expiry**: `12/30`
  - **CVV**: `123`
  - **OTP**: `123456`
- **Execution Steps**:
  1. In Employee Panel, complete enrollment and click "Pay ₹1999 Now".
  2. Razorpay checkout modal opens. Select Card payment using test details.
  3. Complete OTP verification.
- **Pass Criteria**: Payment completes, Razorpay fires live HMAC-SHA256 signed `payment.captured` webhook, business flips to `active`, and setup QR is generated.

---

### C2: Brevo Email & FCM Push Notification Delivery
- **Verifies**: Real email dispatch via Brevo API & FCM push notifications (`08-notifications-system.md`).
- **Prerequisites**: `BREVO_API_KEY` set in Firebase Secret Manager; valid recipient email.
- **Execution Steps**:
  1. Trigger cash payment verification or renewal reminder for an owner email account.
  2. Check inbox of recipient email address (and Spam folder).
- **Pass Criteria**: HTML email with brand styling and action link is delivered to inbox within 60 seconds.

---

### C3: Customer Review Page on Real iPhone (Safari)
- **Verifies**: Native iOS Safari clipboard copy, Google Maps app deep-link handoff, and WhatsApp `wa.me` handoff.
- **Device**: Physical iPhone running iOS 16+.
- **Execution Steps**:
  1. Scan branch QR code or open `https://<hosting-domain>/r/<branch_id>` in Safari on iPhone.
  2. Select 5 stars, select category chips, tap "Copy Review & Open Google".
  3. Verify iOS system popup: `"Review Copied to Clipboard"`.
  4. Verify native Google Maps app opens directly to the business review modal.
  5. Repeat with 1 star — verify native WhatsApp app opens with pre-filled message to `91...`.
- **Pass Criteria**: Seamless native app handoffs with pre-filled text on iOS Safari.

---

### C4: Physical Acrylic Standee QR Code Scan Resolution
- **Verifies**: Printed QR code scanning via native iPhone Camera / Android Lens.
- **Prerequisites**: Printed acrylic standee QR code or screen-displayed QR code PNG.
- **Execution Steps**:
  1. Open default Camera app on iOS or Android. Point lens at the printed QR code.
  2. Tap the detected URL banner (`https://<domain>/r/<branch_id>`).
- **Pass Criteria**: Camera instantly detects QR code and navigates directly to the review landing page for that exact branch.
