# 🧪 COMPLETE SYSTEM TESTING & DEPLOYMENT GUIDE

> **Beginner-Friendly Guide**: Follow this step-by-step document to test the entire platform locally using the **Firebase Emulator Suite** or live in production. Every command can be copied and pasted directly into your terminal.

---

## 🔑 TEST LOGIN CREDENTIALS (ALL ROLES)

> **Important**: These credentials are created by the seed script and work **only in the local emulator**. They do not exist in production.

| Role | Email | Password | Dashboard |
|------|-------|----------|-----------|
| **Admin** | `admin@test.com` | `Test1234!` | Full platform admin — manages employees, businesses, templates, commission queue |
| **Employee A** | `employee@test.com` | `Test1234!` | Employee dashboard — enroll businesses, manage standees, view commissions |
| **Employee B** | `employee.b@test.com` | `Test1234!` | Second employee for cross-access testing (must NOT see Employee A's businesses) |
| **Owner** | `owner@test.com` | `Test1234!` | Business owner dashboard — view analytics, manage categories, renew subscription |

> 💡 **How does a new business owner log in?** When an employee enrolls a business, the owner email provided during enrollment becomes the owner's login. The owner account is provisioned automatically. Before cash/payment confirmation, the owner can still log in and sees a "Pending Activation" banner. After Admin confirms cash payment, the dashboard unlocks fully.

---

## 🛠️ PREREQUISITES & ENVIRONMENT

Before running tests, make sure you have:
1. **Node.js** (v18+) installed (`node -v`).
2. **Flutter SDK** (3.x+) installed (`flutter --version`).
3. **Firebase CLI** installed (`npm install -g firebase-tools` or `npx firebase --version`).

---

## 🅰️ SECTION A — EMULATOR TESTING (FAST, LOCAL & SAFE)

Local emulator testing runs entirely on your machine. No real credit cards, SMS, or live database mutations occur.

### Step 1: Start the Firebase Emulator Suite

Open **Terminal 1** and run:

```bash
# Terminal 1: Start local emulators
npm run emulators
```

> 💡 **Keep Terminal 1 open!** The emulators will print these URLs:
> - **Emulator UI**: `http://127.0.0.1:4000` (View Auth users, Firestore DB, Storage)
> - **Hosting Emulator**: `http://127.0.0.1:5002` (Local web server)
> - **Functions Emulator**: `http://127.0.0.1:5001`
> - **Auth Emulator**: `127.0.0.1:9099`
> - **Firestore Emulator**: `127.0.0.1:8080`

Open a **SECOND terminal window (Terminal 2)** for all remaining commands below.

---

### Step 2: Seed the Local Emulator Database

In **Terminal 2**, seed test users and data:

```bash
# Terminal 2: Seed test users (admin, employee, owner) into Auth + Firestore
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
node scripts/seed-employee-user.js

# Seed category phrase templates
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
node scripts/seed-firestore.js

# Seed an active business for the employee to see
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
node scripts/seed-active-business.js
```

> After seeding, you should see a summary of all test credentials printed in the terminal.

---

### 🚀 EASIEST PATH: Test Admin / Employee / Owner Panels in Interactive Debug Mode

To test the Flutter Web panel interactively with hot-reload connected to the emulator:

```bash
# Terminal 2: Run Flutter Web panel connected to local emulator
cd admin_panel
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

---

### 🌐 FULL SERVED SITE PATH: Test Panels + Review Page + Rewrites (One-Command Build)

To build and serve the complete site (`/` for Flutter Panel, `/r/{branch_id}` for Customer Review Page) via the Firebase Hosting emulator:

```bash
# Terminal 2: One-command web build & assembly for Emulator
npm run build:web:emulator

# Restart the Firebase hosting emulator if needed:
npm run emulators
```

Then open `http://127.0.0.1:5002` in your browser!

---

## 📋 END-TO-END MANUAL QA TEST FLOW (T1 – T18)

### T1: Access Firebase Emulator UI
- **What it checks**: Confirms local emulator suite is active.
- **Action**: Open `http://127.0.0.1:4000` in your browser.
- **Pass Criteria**: You see tabs for **Authentication**, **Firestore**, and **Logs**.

---

### T2: Admin Login & Platform Dashboard Overview
- **What it checks**: Admin role login, custom claims, and aggregate stats.
- **Credentials**: `admin@test.com` / `Test1234!`
- **Action**:
  1. Open `http://127.0.0.1:5002` (or Flutter debug window).
  2. Log in with **admin@test.com** / **Test1234!**
  3. Navigate to **Platform Stats**.
- **Pass Criteria**: Admin metrics (total active businesses, total revenue, commission totals) load dynamically without errors.

---

### T3: Employee Account Creation & Login
- **What it checks**: Admin creation of an employee account + custom claims assignment.
- **Action**:
  1. In Admin Panel, navigate to **Employees** tab → **Add New Employee**.
  2. Fill in: Name (`John Sales`), Email (`john.sales@example.com`), Phone (`+919876543210`), Password (`Employee123!`).
  3. Click **Create Employee Account**.
  4. Log out of Admin, and log into `john.sales@example.com` / `Employee123!`.
- **Pass Criteria**: Sign-in succeeds and lands on the **Employee Dashboard** showing 0 initial enrollments.
- **Alternative**: Use the pre-seeded employee account **employee@test.com** / **Test1234!** to skip account creation.

---

### T4: Enroll New Business (Employee Flow with Google Places Search)
- **What it checks**: Google Places search integration (or mock fallback), draft business creation, branch allocation.
- **Credentials**: `employee@test.com` / `Test1234!` (or any employee account)
- **Action**:
  1. In Employee Panel, tap **+ Enroll Business**.
  2. Fill in business details: Brand Name, Category, Owner Name/Email/Phone.
  3. In the branch form, type a business name and city in the Google Places search field.
     - **With API key configured**: Real Google Places results appear.
     - **Without API key (default emulator)**: Mock candidates appear (e.g. "Business Name - Main Branch").
  4. Select a candidate or enter address manually.
  5. **WhatsApp Monitor shortcut**: Click **"Same as Owner"** to copy the owner's phone number as the WhatsApp monitor.
  6. Submit the enrollment form.
- **Pass Criteria**: Business draft created in Firestore with `subscription_status: "pending_payment"` and assigned `enrolled_by: <employee_uid>`.

---

### T5: Cash Payment & Business Activation (Employee + Admin Two-Step)
- **What it checks**: Employee cash collection at checkout → Admin confirms deposit → Business activates.
- **Flow**:

  | Step | Who | Action |
  |------|-----|--------|
  | 1 | **Employee** | On the Payment screen after enrollment, click **"Collect Cash Payment"**. This logs a commission record with `employee_collected: true` and `status: pending`. |
  | 2 | **Admin** | Log in as **admin@test.com** / **Test1234!**. Navigate to **Commission Queue** tab. Find the pending record and click **"Confirm Cash Received (Admin)"**. |
  | 3 | **System** | Commission record status flips to `verified`. Business `subscription_status` flips from `pending_payment` → `active`. `renewal_date` is set to +365 days. |

- **Pass Criteria**: Business shows as **Active** in both Admin and Employee panels. Owner can now see the full dashboard (no more "Pending Activation" banner).

> ⚠️ **Owner is NOT part of the cash confirmation flow.** The two-step gate is Employee (collects cash) + Admin (confirms deposit).

---

### T6: Standee QR Code Generation
- **What it checks**: Automated QR code PNG generation for standees.
- **Action**:
  1. In Admin/Owner panel, click **Download QR Code** or **View Standee PDF**.
- **Pass Criteria**: High-resolution QR code PNG generated pointing to `https://<domain>/r/<branch_id>`.

---

### T7: Customer Review Page — High Rating Route (5-Star → Google Maps)
- **What it checks**: Star routing config, Google Maps redirect, clipboard phrase copying.
- **Action**:
  1. Open `http://127.0.0.1:5002/r/test_branch_001` in browser.
  2. Tap **5 Stars**.
  3. Select positive phrase chips (e.g. "Great flavor", "Friendly staff").
  4. Tap **Post Review on Google**.
- **Pass Criteria**: Assembled review text is copied to clipboard, scan log is recorded in Firestore with `star_rating: 5`, and Google Maps URL opens in a new tab.

---

### T8: Customer Review Page — Private Feedback Route (1-Star → WhatsApp / Internal)
- **What it checks**: Low rating routing (1-3 stars) preventing negative public reviews.
- **Action**:
  1. Open `http://127.0.0.1:5002/r/test_branch_001`.
  2. Tap **1 Star**.
  3. Enter feedback text ("Service was slow").
  4. Tap **Send Private Feedback**.
- **Pass Criteria**: WhatsApp opens with pre-filled feedback message (or internal feedback logged), scan log created with `action_taken: "whatsapp"`, and public Google Maps is NOT opened.

---

### T9: Review Template System & Phrase Pool Selection
- **What it checks**: Category phrase pool assembly and duplicate review prevention.
- **Action**:
  1. Open `http://127.0.0.1:5002/r/test_branch_001`.
  2. Select and deselect different category chips.
- **Pass Criteria**: Text box updates dynamically with randomized, natural phrase variations.

---

### T10: Business Owner Dashboard & Analytics
- **What it checks**: Owner login, branch metrics, and scan log summary.
- **Credentials**: `owner@test.com` / `Test1234!`
- **Action**:
  1. Log in as **owner@test.com** / **Test1234!**
  2. If the business is still `pending_payment`, you'll see a **"Pending Activation"** banner — this is expected before Admin confirms cash.
  3. After Admin confirms cash (T5), refresh the page — full dashboard appears.
- **Pass Criteria**: Owner views scan count, star breakdown chart, and standee shipping status.

> 💡 **Owner login before payment confirmation**: The owner CAN log in before cash is confirmed. They see a "Pending Activation" banner with a message that the system will activate once Admin verifies the payment.

---

### T11: Employee My Profile & Document Upload
- **What it checks**: Employee document upload (Aadhaar/PAN/Bank passbook) to Firebase Storage.
- **Credentials**: `employee@test.com` / `Test1234!`
- **Action**:
  1. Log into Employee Panel → **My Profile / My Details**.
  2. Upload document PDF/image (`< 5MB`).
  3. Fill in bank payout details (UPI ID / Account number).
- **Pass Criteria**: Document uploaded to `employee_docs/{uid}/` in Firebase Storage; Firestore status updated to `pending_verification`.

---

### T12: Admin Document Verification Gate
- **What it checks**: Admin KYC verification of employee payout documents.
- **Credentials**: `admin@test.com` / `Test1234!`
- **Action**:
  1. In Admin Panel → **Employees** tab → Select Employee.
  2. View uploaded documents.
  3. Click **Approve Documents**.
- **Pass Criteria**: Firestore status flips to `documents_verified: "verified"`.

---

### T13: Admin Commission Queue — Verify, Pay, and Delete Records
- **What it checks**: Admin commission verification, payout, and record deletion.
- **Credentials**: `admin@test.com` / `Test1234!`
- **Action**:
  1. Navigate to **Commission Queue** tab.
  2. **Status badges**: Each record shows "Employee Collected" (✅/⏳) and "Admin Cash Received" (✅/⏳).
  3. Click **"Confirm Cash Received (Admin)"** on a pending record → status flips to `verified`, business activates.
  4. To delete an erroneous record: Click **"Delete"** on a pending/disputed record → confirm in the dialog.
  5. To mark as paid: Click **"Mark Paid"** on a verified record → enter UTR reference → confirm.
- **Pass Criteria**: Commission status updates correctly; deleted records disappear from queue; paid records show `payout_reference` and `date_paid`.

---

### T14: Admin Business Management — View, Edit, Filter All Businesses
- **What it checks**: Admin can see and edit all enrolled businesses with filtering.
- **Credentials**: `admin@test.com` / `Test1234!`
- **Action**:
  1. Navigate to **All Businesses & Overrides** tab.
  2. **Filter by status**: Click filter chips (All / Active / Pending / Grace / Deleted).
  3. **Filter by date**: Click **"Date Filter"** → select a date range → businesses are filtered by enrollment date.
  4. **View details**: Each card shows Brand Name, Status badge, Owner, Enrolled By, Created date, Renewal date.
  5. **Edit business**: Click **"Edit Business"** → modify Brand Name, Category, Owner Name/Email/Phone, Status → **Save Changes**.
  6. **Override subscription**: Click **"Override"** → change status, renewal date, or grace period → enter reason → **Apply Override**.
- **Pass Criteria**: Filters work correctly; edits persist after refresh; override audit log created in `subscription_override_logs`.

---

### T15: Admin Template Management
- **What it checks**: Admin can add, edit, and manage category templates.
- **Credentials**: `admin@test.com` / `Test1234!`
- **Action**:
  1. Navigate to **Templates** tab.
  2. Create a new template or edit an existing one.
- **Pass Criteria**: Template appears in the `category_templates` collection in Firestore.

---

### T16: Employee Offboarding & Reassignment
- **What it checks**: Safe offboarding of employees without orphaned business records.
- **Credentials**: `admin@test.com` / `Test1234!`
- **Action**:
  1. In Admin Panel → **Employees** tab, select employee → **Offboard Employee**.
  2. Select target employee or Admin for bulk reassignment.
- **Pass Criteria**: Employee status set to `active: false`, custom claim disabled, and all managed businesses updated to `currently_managed_by: target_uid`.

---

### T17: Enrollment Form Reset (No Stale Data)
- **What it checks**: After enrolling a business, starting a new enrollment resets all form fields.
- **Action**:
  1. Complete a business enrollment (T4).
  2. Without refreshing, click **+ Enroll Business** again.
- **Pass Criteria**: All form fields (business name, owner phone, address, etc.) are blank — no pre-filled data from the previous enrollment.

---

### T18: Production Security Hardening QA Suite (Automated)

Run the automated security rules and hardening suite against the emulator:

```bash
# Terminal 2: Run security hardening assertions
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/test-security-hardening.js
```

- **Pass Criteria**: Prints `🎉 PRODUCTION SECURITY HARDENING QA PASSED SUCCESSFULLY!`.

---

## ❓ TROUBLESHOOTING & COMMON PROBLEMS

| Problem | Cause | Solution |
|---|---|---|
| **"Invalid ID / Password" on login** | Seed script not run, or emulators restarted (Auth data lost) | Re-run: `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node scripts/seed-employee-user.js` |
| **Blank screen on `127.0.0.1:5002`** | Missing `script-src 'unsafe-eval' 'wasm-unsafe-eval'` in CSP header or panel built without emulator flag | Run `npm run build:web:emulator` and refresh browser. |
| **Port 8080 / 9099 / 5002 taken error** | Previous emulator process still running in background | Run: `kill -9 $(lsof -t -i:8080 -i:9099 -i:5002 -i:4000 -i:5001)` |
| **Category templates not showing on review page** | Seed script did not target local emulator | Ensure `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` is set before running `node scripts/seed-firestore.js`. |
| **Permission Denied in Firestore Console** | User claims not assigned | Run `seed-employee-user.js` or set custom claim via Admin SDK function. |
| **Google Places search returns mock results** | PLACE_API_KEY not configured in `functions/.env.local` | This is expected in the emulator. Mock candidates work for testing. For real results, set `PLACE_API_KEY=your_key` in `functions/.env.local`. |
| **Employee profile is blank after creation** | Profile sub-map not yet filled | The model reads top-level `name`/`email` fields as fallback. Employee should visit My Profile to complete details. |

---

## 🅱️ SECTION B — LIVE PRODUCTION TESTING (BEFORE FIRST CLIENT)

Perform these steps when preparing to launch the live site on Firebase Hosting.

### 1. Build and Deploy to Production

```bash
# 1. Build production web bundle (connects to LIVE Firebase)
npm run build:web

# 2. Deploy rules, functions, indexes, and hosting to live project
firebase deploy
```

Your live site URL will be displayed in the terminal:
`https://review-system-prod-49b7a.web.app`

---

### 2. Live Device & Real-Service Testing Protocol

The following tests **MUST** be performed on a real mobile device (iPhone / Android) against live production services:

#### 📱 Live Test 1: Real iPhone / Android Camera QR Scan Handoff
1. Print or display the generated branch QR code PNG on a desktop screen.
2. Open native **Camera App** on an iPhone or Android phone.
3. Point camera at QR code and tap the notification banner.
4. **Pass Criteria**: Opens `https://<your-domain>.web.app/r/<branch_id>` directly in mobile Safari / Chrome browser without landing errors.

#### 📋 Live Test 2: Mobile Safari Clipboard & App Handoff
1. On iPhone Safari, open customer review page.
2. Select 5 stars → select review chips → tap **Post Review on Google**.
3. **Pass Criteria**: iOS clipboard prompt appears ("Allow Paste"), review text is copied, and Google Maps app opens smoothly.

#### ✉️ Live Test 3: Real Brevo Email Sender Verification
1. Trigger employee creation or owner provisioning email.
2. Check recipient inbox.
3. **Pass Criteria**: Email arrives from verified domain (e.g. `notifications@yourdomain.com`). If email lands in spam, verify SPF/DKIM DNS TXT records in Brevo dashboard.

#### 💳 Live Test 4: Live Razorpay Payment Gateway (Test Mode)
1. Complete business enrollment using Razorpay test card credentials (`4111 1111 1111 1111`, OTP `123456`).
2. **Pass Criteria**: Razorpay checkout modal opens, payment succeeds, webhook fires, and business status flips to `active`.
