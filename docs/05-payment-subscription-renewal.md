# 05 — Payment, Subscription & Renewal Enforcement

**Depends on:** `00-architecture-and-schema.md`, `06-commission-tracking.md`, `08-notifications-system.md`

## Payment Gateway
- **Razorpay**, onboarded as Individual/Sole Proprietor (no company registration needed) — PAN + bank account + ID proof.
- Use **Razorpay Subscriptions API** for the ₹999/year renewal so it can auto-collect on schedule rather than requiring manual chase every year.
- ₹1999 one-time setup fee: a standard one-time payment link/order at enrollment time.
- Optional: pass the gateway's convenience fee to the customer at checkout (Instamojo supports this natively; check current Razorpay equivalent) if you want the ₹1999/₹999 to net out exactly.
- Optional credibility step: free Udyam (MSME) registration — smooths gateway approval, no legal firm required.

## Renewal Enforcement — Exact Rules
- `businesses/{id}.subscription_status` has three states: `"active" | "grace_period" | "deleted"`.
- On `renewal_date` reached without payment:
  - Status flips to `"grace_period"`.
  - `grace_period_ends = renewal_date + 30 days`.
  - Customer-facing QR/NFC link (see `01`) starts showing "temporarily unavailable" instead of the review flow.
  - **Owner dashboard access remains fully available** during grace period, specifically so they can pay and reactivate.
- On `grace_period_ends` reached without payment:
  - Status flips to `"deleted"`.
  - Business data is deleted (define exact deletion scope — e.g. scan logs, branch docs — before building this; don't delete `commission_records`, since those are your own financial audit trail, not the client's data).
- A **scheduled Cloud Function** (daily) checks all businesses' `renewal_date`/`grace_period_ends` and performs these status flips automatically.

## Payment Webhook Flow
1. Owner clicks "Pay Now" on dashboard (`02`) or employee/admin processes it during enrollment.
2. Razorpay checkout completes → webhook fires to a Cloud Function.
3. Cloud Function verifies the webhook signature (security — don't trust unverified webhook calls), then:
   - Updates `businesses/{id}.renewal_date` (extends by 1 year) and `subscription_status` back to `"active"`.
   - Creates a `commission_records` entry with `payment_mode: "online"`, `status: "verified"` (see `06`) — this is automatic, no manual admin step needed for online payments specifically.

## Notifications Tied to This Flow
See `08-notifications-system.md` for the full renewal reminder schedule (30/15/7/1 days before expiry) and channels (email, dashboard banner, push).
