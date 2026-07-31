# 08 — Notifications System (Renewal Reminders)

**Depends on:** `00-architecture-and-schema.md`, `05-payment-subscription-renewal.md`, `06-commission-tracking.md`

## Trigger
A scheduled Cloud Function runs **daily**, checking `renewal_date` on every `businesses/{id}` document.

## Recipients & Schedule
| Recipient | Trigger point | Purpose |
|---|---|---|
| Business Owner | 30 / 15 / 7 / 1 days before expiry | Prompt to pay ₹999 to keep access active |
| Enrolling Employee (`enrolled_by` or `currently_managed_by`) | Same windows | Personal follow-up for retention |
| Admin | Weekly digest (not per-business — avoids notification fatigue at scale) | Overview of upcoming renewals, flag high-value accounts |

## Channels (Free by Default)
1. **Email** — business owner's email, collected at enrollment (`03`). Use Firebase Extensions/SMTP for this volume.
2. **Dashboard banner** — always shown on login, zero cost.
3. **Web Push (Firebase Cloud Messaging)** — free, works even without opening the dashboard, *if* the owner has granted browser notification permission. Prompt for this permission once during onboarding (`03`), don't wait until renewal time to ask.
4. SMS / WhatsApp Business API — **paid**, optional upgrade later. Not required for launch since email + push + dashboard covers this at zero incremental cost. (Note: `wa.me` links used elsewhere in this system are free only for customer-initiated chats — a business-initiated renewal reminder over WhatsApp needs the paid Business API, which is why it's not a default channel here.)

## Also Used For (Reuse This System, Don't Build a Second One)
- Cash payment verification messages to business owners (see `06-commission-tracking.md`) — same email/push/dashboard infrastructure, just a different message template and trigger event.
