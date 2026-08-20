# Appnexa Admin Panel — Complete Function & Flow Guide

> This document describes **every function and flow** available in the Admin Dashboard UI.  
> Login URL: `https://review-system-prod-49b7a.web.app` → sign in with an admin-role Firebase Auth account.

---

## Table of Contents

1. [Dashboard Overview & Navigation](#1-dashboard-overview--navigation)
2. [Tab 1: Platform Stats](#2-tab-1-platform-stats)
3. [Tab 2: Enroll Business](#3-tab-2-enroll-business)
4. [Tab 3: Employee Management](#4-tab-3-employee-management)
5. [Tab 4: Category Templates](#5-tab-4-category-templates)
6. [Tab 5: Subscription Overrides](#6-tab-5-subscription-overrides)
7. [Tab 6: Commission & Payment Queue](#7-tab-6-commission--payment-queue)
8. [Business Detail Screen (Shared)](#8-business-detail-screen-shared)
9. [Share Review QR & Link](#9-share-review-qr--link)

---

## 1. Dashboard Overview & Navigation

### Access Control
- Only users with `role == 'admin'` in their Firebase Auth custom claims can access the dashboard.
- Non-admin users see an "Access Denied" screen with a logout button.

### Navigation Layout
| Screen Width | Navigation Type |
|---|---|
| > 900px (Desktop) | **NavigationRail** on the left side |
| ≤ 900px (Mobile) | **BottomNavigationBar** at the bottom |

### 6 Tabs
| # | Tab Name | Icon | Purpose |
|---|---|---|---|
| 1 | **Stats** | 📊 analytics | Platform-wide KPIs, revenue, renewals |
| 2 | **Enroll** | 🏪 add_business | Directly enroll a new business |
| 3 | **Employees** | 👥 people | Create, manage, offboard employees |
| 4 | **Templates** | 📚 library_books | CRUD review phrase templates |
| 5 | **Overrides** | 📅 edit_calendar | Manual subscription overrides |
| 6 | **Commission** | ✅ verified | Cash payment verification & payouts |

### AppBar Actions
- **Admin email chip** — shows the logged-in admin's email
- **Logout button** — confirms and signs out

---

## 2. Tab 1: Platform Stats

**File:** `admin_platform_stats_tab.dart`  
**Provider function:** `refreshPlatformStats()`

### What it shows

#### KPI Cards (Top Grid)
Four cards in a responsive grid showing live Firestore `count()` aggregation queries:

| Card | What it counts | Query |
|---|---|---|
| **Total Paying Businesses** | Active + Grace Period + Deleted | `subscription_status in ['active', 'grace_period', 'deleted']` |
| **Active Subscriptions** | Currently active | `subscription_status == 'active'` |
| **Grace Period** | Expired but in grace window | `subscription_status == 'grace_period'` |
| **Pending Payment Drafts** | Not yet paid | `subscription_status == 'pending_payment'` |

> **Example:** If you have 50 active, 5 grace, 3 deleted, and 10 pending — Total shows 58, Active shows 50, Grace shows 5, Pending shows 10.

#### Revenue Snapshot
- **Formula:** `(active_count × ₹1999) + (grace_count × ₹999)`
- Shows the estimated revenue based on setup fees and renewal pricing.

#### Renewal Breakdown
Shows how many active businesses have `renewal_date` falling within:

| Window | Color | Meaning |
|---|---|---|
| Due in 30 Days | 🔵 Blue | Upcoming but not urgent |
| Due in 15 Days | 🟡 Amber | Should start outreach |
| Due in 7 Days | 🟠 Orange | Urgent — contact now |
| Due Tomorrow/Today | 🔴 Red | Critical — will lapse if not renewed |

#### All Enrolled Businesses Table
Below the stats, a searchable/filterable table of **all** businesses (max 100, newest first).

**Functions available on this table:**

##### `Refresh Stats` button (🔄)
- **What it does:** Re-runs all `count()` aggregation queries and refreshes KPIs.
- **When to use:** After making changes (overrides, enrollments) to see updated numbers.
- **Example:** You just activated a cash business → click Refresh → Active count goes up by 1.

##### `Search` field
- **What it does:** Filters the table by brand name or owner email (client-side).
- **Example:** Type "chai" → shows only businesses with "chai" in their name.

##### `Status filter chips` (All / Active / Pending / Grace)
- **What it does:** Filters the table by subscription status.
- **Example:** Click "Pending" → see only pending_payment drafts.

##### `Edit Business` (pencil icon per row)
- **What it does:** Opens a dialog to edit: Brand Name, Category Type, Owner Name, Owner Email, Owner Phone, Subscription Status.
- **When to use:** To correct typos, update owner contact info, or manually change status.
- **Example:** Owner changed their email → click edit → update email → Save.

##### `View Details` (arrow icon per row)
- **What it does:** Navigates to the [Business Detail Screen](#8-business-detail-screen-shared).

---

## 3. Tab 2: Enroll Business

**File:** `enroll_screen.dart`  
**Provider:** `EnrollProvider`

This is the **same enrollment form** used by employees, but when accessed by admin it has no restrictions (admin can enroll for any category, any location).

### Step-by-Step Flow

#### Step 1: Choose Mode
- **Single Location** — one branch, branch name auto-set to business name
- **Multiple Branches** — N branches with individual names, addresses, WhatsApp numbers

#### Step 2: Business-Level Fields
| Field | Required | Description |
|---|---|---|
| Brand Name | ✅ | Business brand/trade name |
| Category | ✅ | Dropdown from category templates |
| Logo | Optional | Upload business logo (min 500×500px enforced) |
| Owner Name | ✅ | Business owner's full name |
| Owner Email | ✅ | Owner's email (used for owner login provisioning) |
| Owner Phone | ✅ | Owner's phone in +91 format |

#### Step 3: Branch-Level Fields (per branch)
| Field | Required | Description |
|---|---|---|
| Branch Name | ✅ (multi) | Name of this location |
| Address | ✅ | Physical address |
| WhatsApp Number | ✅ | Number for negative review alerts |
| WA Monitored By | ✅ | Who monitors the WhatsApp channel |
| Place ID | Optional | Google Place ID for review link |
| Star Routing | ✅ | 1–5 star → thankyou / whatsapp / google |

> **Place ID:** If provided, a `google_review_link` is auto-generated:  
> `https://search.google.com/local/writereview?placeid={PLACE_ID}`

#### Step 4: Submit
- Creates a `businesses` document with `subscription_status = 'pending_payment'`
- Creates branch sub-documents under `businesses/{id}/branches/`
- For admin enrollments, `enrolled_by = 'admin'`

> **Example:** Admin enrolls "Chai Point" with 2 branches (HSR Layout, Koramangala).  
> Result: 1 business doc + 2 branch docs created, status = pending_payment.

---

## 4. Tab 3: Employee Management

**File:** `admin_employees_tab.dart`  
**Provider functions:** `createEmployee()`, `deactivateEmployee()`, `verifyEmployeeDocuments()`

### Functions

#### `Add Employee` button (top-right)
- **What it does:** Opens a dialog to create a new employee Firebase Auth account + Firestore profile.
- **Required fields:**
  - Full Name
  - Email Address
  - Initial Password
  - Phone Number (+91)
  - Address (optional)
- **What happens behind the scenes:**
  1. Calls Cloud Function `createEmployeeAccount`
  2. Creates Firebase Auth user with `role = 'employee'` custom claim
  3. Creates `employees/{uid}` Firestore document with initial metrics (0 enrollments)
- **Example:** Create "Rahul Sharma" with email `rahul@appnexa.co.in` → he can now log in and enroll businesses.

#### Employee Card (expandable per employee)
Each employee shows:
- **Header:** Name, email, phone, status (ACTIVE/INACTIVE), documents verification badge
- **Expand** to see details:

##### Metrics Row
| Metric | Description |
|---|---|
  | Total Enrollments | All-time businesses enrolled by this employee |
  | This Month | Enrollments in current calendar month |
  | Pending Commission | ₹ amount of unverified cash commissions |
  | Verified Commission | ₹ amount of verified but unpaid commissions |
  | Paid Commission | ₹ amount of fully paid commissions |

##### `Verify KYC Docs` / `Reject KYC Docs` buttons
- **What it does:** Sets `documents_verified` to `'verified'` or `'rejected'` on the employee record.
- **When to use:** After manually reviewing the employee's uploaded ID documents and bank details.
- **Example:** Employee uploaded PAN + Aadhaar → Admin reviews → clicks "Verify KYC Docs" → badge turns green.

##### Managed Businesses List
- Shows all businesses where `currently_managed_by == employee.uid`
- Displays brand name, status, and category for each.

##### `Offboard Employee` button
- **What it does:** Deactivates the employee and bulk-reassigns all their managed businesses to `currently_managed_by = 'admin'`.
- **Confirmation dialog** explains the impact clearly.
- **Preserves `enrolled_by_original`** — the original enrollment record stays intact.
- **Example:** Employee "Rahul" leaves → click Offboard → his 15 businesses now show as managed by Admin → Rahul can no longer log in.
- **Cloud Function:** Calls `offboardEmployee`

---

## 5. Tab 4: Category Templates

**File:** `admin_templates_tab.dart`  
**Provider functions:** `createCategoryTemplate()`, `addPhraseVariant()`, `retirePhraseVariant()`

Category templates define the **review phrase pools** shown to customers on the review page. Each business category (bakery, salon, gym, etc.) has its own template with multiple phrase variants.

### Functions

#### `Create Template` button
- **What it does:** Creates a new category template in Firestore (`category_templates/{templateId}`).
- **Required fields:**
  - Template ID (e.g., `bakery_v1`)
  - Business Type Label (e.g., `Bakery / Confectionery`)
  - First Category Name (e.g., `Taste & Freshness`)
  - Initial Review Phrase Variant (e.g., `Freshly baked goods and amazing cakes!`)
- **Example:** Create template for "Gym / Fitness Center" with phrase "Best gym with modern equipment!"

#### Template Detail Panel (select a template from the list)
Shows all categories and their phrase pool versions.

##### `Add Phrase Variant`
- **What it does:** Adds a new phrase to an existing category's pool.
- **Fields:** Category Name, Pool Version (v1/v2/v3), Language (en), Phrase text
- **Example:** Add variant to Bakery/Taste: "The pastries here are absolutely divine!"
- **Why multiple variants?** The review page randomly picks from the pool so reviews look natural, not templated.

##### `Retire Phrase` (🗑️ icon)
- **What it does:** Removes a specific phrase from the pool (soft delete).
- **When to use:** If a phrase is inappropriate or outdated.
- **Example:** Retire "Best place ever!" because it's too generic.

---

## 6. Tab 5: Subscription Overrides

**File:** `admin_subscription_overrides_tab.dart`  
**Provider functions:** `updateBusinessDetailsAdmin()`, `overrideSubscriptionStatus()`

This tab shows **all businesses** with advanced filtering and two admin actions: Edit Business and Override Subscription.

### Filters Available

| Filter | Type | Description |
|---|---|---|
| Status chips | All / Active / Pending / Grace / Deleted | Filter by subscription_status |
| Date range picker | Calendar | Filter by `created_at` range |
| Month dropdown | Jan–Dec | Filter by enrollment month |
| Year dropdown | 2024–now | Filter by enrollment year |
| Mobile search | Text | Search by owner phone number |

### Count Summary Badges
Shows: Total businesses, Currently showing (after filters), Active count, Pending count.

### Functions

#### `Edit Business` button (per row)
Opens a full edit dialog with fields:
- Brand Name, Category Type, Owner Name, Owner Email, Owner Phone
- Subscription Status dropdown (Active / Grace Period / Pending Payment / Deleted)

> **Example:** Owner phone changed from +91-98765 to +91-98766 → Edit → update phone → Save.

#### `Override` button (per row)
Opens the **Subscription Override dialog** with fields:

| Field | Description |
|---|---|
| Subscription Status | Dropdown: Active / Grace Period / Deleted / Pending Payment |
| Renewal Date | Date picker — set new expiry date |
| Grace Period Ends | Date picker — only shown when status = grace_period |
| Reason for Override | Required text — explains why the override was made |

**What happens behind the scenes:**
1. Updates the business document with new status/dates
2. Creates an audit log entry in `subscription_override_logs` collection with:
   - business_id, new_status, renewal_date, grace_period_ends
   - overridden_by (admin UID), reason, timestamp

> **Example — Extend Grace Period:**  
> A business expired but owner promised to pay next week.  
> Override → set status "Grace Period" → set Grace Period Ends to 7 days from now → reason "Owner requested extension, payment expected by Friday" → Save.

> **Example — Reactivate a Deleted Business:**  
> Owner paid after lapsing.  
> Override → set status "Active" → set Renewal Date to 365 days from now → reason "Late payment received, reactivating" → Save.

> **Example — Force Pending:**  
> Something went wrong with payment.  
> Override → set status "Pending Payment" → reason "Payment gateway error, resetting to pending" → Save.

#### `View Details` (eye icon per row)
Navigates to the [Business Detail Screen](#8-business-detail-screen-shared).

---

## 7. Tab 6: Commission & Payment Queue

**File:** `admin_commission_queue_screen.dart`  
**Provider functions:** `adminConfirmCashPayment()`, `markCommissionPaid()`, `deleteCashCommissionRecord()`

This tab is a **real-time stream** of commission records that need admin action. It automatically updates when records change.

### Commission Record Card
Each card shows:
- **Business name & amount** (e.g., "Chai Point — ₹500")
- **Payment mode** (Cash or Online/Razorpay)
- **Employee** who enrolled (or "Admin" for direct enrollments)
- **Date** of the commission claim
- **Status chip** (PENDING / VERIFIED / DISPUTED / PAID)
- **Admin Confirmed badge** (✅ Confirmed or ⏳ Pending)

### Functions

#### `Confirm Cash Received (Admin)` button
- **Visible when:** `adminConfirmed == false` (admin hasn't confirmed yet)
- **What it does (NEW MODEL — single-step activation):**
  1. Marks the commission record as `status = "verified"`, `admin_confirmed = true`
  2. **Activates the associated business** — sets `subscription_status = "active"`, `renewal_date = +365 days`, `payment_mode = "cash"`
  3. The business is now fully live — QR generation triggers, owner can start using the service
- **Cloud Function:** Calls `confirmCashPaymentAdmin`
- **Example:**  
  Employee collected ₹1999 cash from "Chai Point" → admin verifies the cash is deposited →  
  clicks "Confirm Cash Received" → business becomes active immediately, no separate override needed.

> **IMPORTANT:** This is a **single-action activation** — confirming cash receipt = activating the business.  
> You do NOT need to go to Overrides tab to manually flip pending → active.

#### `Mark Paid` button
- **Visible when:** `status == "verified"` (cash confirmed but commission not yet paid to employee)
- **What it does:** Opens a dialog asking for the Payout Reference (UTR / Transaction ID).
- **Required field:** Payout Reference (e.g., `UTR_1234567890`)
- **What happens:** Sets `status = "paid"`, `payout_reference = {UTR}`, `paid_by = {adminUid}`
- **Example:**  
  Commission of ₹500 verified → Admin transfers ₹500 to employee's bank →  
  clicks "Mark Paid" → enters UTR `UTIB123456` → record moves to "PAID" status.

#### `Delete` button
- **Visible when:** `status == "pending"` or `status == "disputed"`
- **What it does:** Permanently deletes the commission record.
- **Confirmation dialog** warns this cannot be undone.
- **When to use:** Duplicate records, test data, or resolved disputes.
- **Example:** Accidental duplicate cash entry → Delete → confirm → record gone.

#### Dispute Handling
If an owner reports that they didn't receive the cash payment:
- The record shows a red **"⚠️ Owner Reported Dispute"** banner
- The dispute reason is displayed
- Admin can either:
  - **Confirm** (if admin verifies the cash was actually received) → overrides the dispute
  - **Delete** (if the record is fraudulent)

---

## 8. Business Detail Screen (Shared)

**File:** `business_detail_screen.dart`  
**Used by:** Both admin and employee panels (same screen, accessed via `/business/:id`)

When you tap "View Details" on any business, you see:

### Business Summary Card
- Brand name with initial avatar
- Status badge (Active / Pending / Grace / Due Soon / Deleted)
- Category, owner email, renewal date, business ID
- "Reassigned" banner if the business was reassigned from another employee

### Pending Payment Panel (only for pending_payment status)
- Amber banner with "Resend Payment Link" button
- **`Resend Payment Link`** — calls Cloud Function `resendPaymentLink`
  - Returns a short URL that can be copied and sent to the owner
  - Shows the URL after generation for easy copy

### Branch Cards
Each branch shows:

| Field | Description |
|---|---|
| Branch Name | Name of the location |
| Address | Physical address |
| WhatsApp | Alert number for negative reviews |
| WA Monitor | Who watches the WhatsApp channel |
| Place ID | Google Place ID (if set) |
| Review Link | Google review link (derived from Place ID) |
| Branch ID | Firestore document ID |

#### `Download Printable QR` button
- **Visible when:** `plain_qr_storage_path` is set (only after activation)
- **What it does:** Opens the plain QR PNG (600×600px) in a new tab for download
- **The QR encodes:** `https://appnexa.co.in/r/{businessId}/{branchId}`

#### Standee Status Dropdown
- **Visible when:** Business is not pending_payment
- **Options:** Not Ordered / Ordered / In Production / Shipped / Delivered
- **What it does:** Updates `standee_status` on the branch document
- **Example:** Acrylic standee shipped → change to "Shipped" → auto-saves

#### Star Routing Table
Shows the 1–5 star routing configuration:

| Star | Route |
|---|---|
| ⭐ 1 | whatsapp (sends negative alert) |
| ⭐ 2 | whatsapp |
| ⭐ 3 | thankyou (shows thank you page) |
| ⭐ 4 | google (redirects to Google review) |
| ⭐ 5 | google |

### Edit FAB (✏️)
- Floating action button that navigates to `BusinessEditScreen`
- Admin can edit all business and branch details

---

## 9. Share Review QR & Link

**File:** `widgets/share_business_qr.dart`  
**Used by:** Both admin and employee panels (inside each Branch Card)

This widget appears on activated business branches only. It provides quick sharing options.

### Functions

#### `Copy Link` button
- **What it does:** Copies the review URL to clipboard
- **URL format:** `https://appnexa.co.in/r/{businessId}/{branchId}`
- **Visual feedback:** Button changes to "Copied!" with a checkmark for 2 seconds
- **Example:** Copy link → paste into email or any messaging app

#### `Download QR` button
- **What it does:** Opens the plain QR PNG (600×600px) in a new tab
- **The QR encodes:** Same URL as Copy Link
- **Use case:** Download and print, or manually attach to WhatsApp message

#### `WA Owner` button (green WhatsApp icon)
- **Visible when:** Owner phone number exists on the business
- **What it does:** Opens `wa.me/{91XXXXXXXXXX}?text={pre-filled message}` in a new tab
- **Pre-filled message:**
  ```
  Here is your Appnexa review QR link:
  https://appnexa.co.in/r/{businessId}/{branchId}

  Share this link with your customers to collect Google reviews!
  ```
- **Example:** Click "WA Owner" → WhatsApp Web opens → message pre-filled → just hit Send

#### `WA Branch` button
- **Visible when:** Branch WhatsApp number is different from owner phone
- **Same behavior** as WA Owner but sends to the branch's WhatsApp number

#### `WA Manager` button
- **Visible when:** WA monitor number is different from both owner and branch numbers
- **Same behavior** but sends to the WhatsApp monitor person

> **NOTE:** WhatsApp (wa.me) can only send **text** — it cannot auto-attach images.  
> To send the QR image: use "Download QR" first, then manually attach it in WhatsApp.

---

## Quick Reference: Admin Workflow Examples

### Workflow 1: Enroll a Business with Cash Payment
1. Go to **Tab 2 (Enroll)** → fill the form → Submit
2. Business created as `pending_payment`
3. Collect cash from the owner
4. Go to **Tab 6 (Commission)** → find the record → click **"Confirm Cash Received"**
5. Business is now **active** — QR generated, owner can start using

### Workflow 2: Extend a Business's Grace Period
1. Go to **Tab 5 (Overrides)** → find the business
2. Click **Override** → set status to "Grace Period" → set Grace Period Ends date
3. Enter reason → Save
4. Audit log created automatically

### Workflow 3: Onboard a New Employee
1. Go to **Tab 3 (Employees)** → click **Add**
2. Fill name, email, password, phone → Create
3. Employee can now log in at the same URL
4. After they upload KYC docs → review and click **Verify KYC Docs**

### Workflow 4: Share QR with a Business Owner
1. Go to any **active business** → View Details
2. On the branch card, find the **"Share Review QR & Link"** panel
3. Click **"WA Owner"** → WhatsApp opens with pre-filled link
4. Optionally: click **"Download QR"** → save the image → attach manually

### Workflow 5: Handle a Disputed Cash Payment
1. Go to **Tab 6 (Commission)** → find the disputed record (red banner)
2. Read the dispute reason from the owner
3. If cash was genuinely received → click **"Confirm Cash Received"** → overrides dispute
4. If fraudulent → click **"Delete"** → removes the record

---

## File Map

| File | Purpose |
|---|---|
| `admin_dashboard_screen.dart` | Main shell with 6-tab navigation |
| `admin_platform_stats_tab.dart` | KPIs, revenue, renewals, all-businesses table |
| `admin_employees_tab.dart` | Employee CRUD, metrics, offboarding |
| `admin_templates_tab.dart` | Category template phrase pool CRUD |
| `admin_subscription_overrides_tab.dart` | Business list with edit + override dialogs |
| `admin_commission_queue_screen.dart` | Cash verification queue + mark paid |
| `business_detail_screen.dart` | Shared business/branch detail view |
| `enroll_screen.dart` | Enrollment form (reused from employee panel) |
| `widgets/share_business_qr.dart` | Share QR/link widget (reused in both panels) |
| `providers/admin_dashboard_provider.dart` | All admin state management + Firestore calls |
