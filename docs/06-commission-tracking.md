# 06 — Commission Tracking (incl. Cash Payments)

**Depends on:** `00-architecture-and-schema.md`, `03-employee-enrollment-panel.md`, `04-admin-panel.md`, `05-payment-subscription-renewal.md`

## Schema
```
commission_records (collection)
  └─ record_id
       - employee_id, business_id
       - amount, payment_mode: "online" | "cash"
       - status: "pending" | "verified" | "paid"
       - date_claimed, date_verified
```

## Online Payments (fully automatic)
- Razorpay webhook confirms payment received (see `05`) → Cloud Function auto-creates a `commission_records` entry with `status: "verified"` → queued for payout to the employee. No manual admin action required.

## Cash Payments (requires verification — this is the fraud-prevention-sensitive path)
1. Employee (in `03`) manually logs a "cash collected" entry: business, amount, date.
2. Record starts as `status: "pending"`.
3. **Two-step verification before it becomes `"verified"`:**
   - **Admin confirms** the cash was actually physically handed over or deposited — a manual approval action in the admin's Commission Verification Queue (`04`).
   - **Business owner confirms independently** via an automated message ("Did you pay ₹1999 in cash to [Employee Name] on [date]? Yes/No") sent through the free notification channels (see `08`).
   - Only when **both** confirmations are in does the record flip to `"verified"`.
4. This closes the main fraud gap: an employee claiming commission for a cash payment that never happened, or one they collected but didn't hand over.

## Payout
- `"verified"` records are eligible for payout (however you run payroll — this doc only covers tracking, not the payout mechanism itself).
- Once paid, flip to `"paid"` with a payout date/reference.

## Views That Read This Data
- Employee's own dashboard (`03`): their pending/verified/paid totals.
- Admin's employee management screen (`04`): same data, for every employee.
- Admin's Commission Verification Queue (`04`): filtered to `payment_mode: "cash"` and `status: "pending"`.
