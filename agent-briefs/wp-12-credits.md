# WP-12 — Credits Ledger

**Phase:** 2 (critical path) · **Hard deps:** wp-03 · **Soft deps:** wp-13 (`order.paid`)

## Goal
An append-only credit ledger: packages grant credits to households; bookings consume them; cancellations return them per policy; credits expire.

## You own
`App.Credits`, controllers `staff/credits/`, `portal/credits/`. Migrations prefixed `credits_`.

## Schemas
- **credit_lots**: household, `source` (`package_purchase|admin_grant|return_grace`), `order_line_id` (nullable), `package_id`, `eligible_offering_ids` (snapshot array; empty = all), `quantity_granted`, `remaining` (cached), `expires_at` (nullable), `granted_at`.
- **credit_ledger_entries**: lot, household, `delta` (+/-), `reason` (`grant|debit|reversal|expire|adjust`), `booking_id` (nullable), `reverses_entry_id` (nullable), `actor`, `note`, `inserted_at`. Never updated or deleted (revoke UPDATE/DELETE for the app role, or use a trigger).
- Invariant: `lot.remaining == sum(entries.delta for lot)` — add a DB-level check job + test.

## Public API
- `grant(household_id, package_id, order_line_id)` (idempotent on `order_line_id`).
- `consume(household_id, offering_id, count, booking_id) :: {:ok, [entry]} | {:error, :insufficient_credits}` — lock eligible lots `FOR UPDATE` ordered by `expires_at NULLS LAST, granted_at`; FIFO by soonest expiry; may span lots. Must run inside the caller's transaction (wp-14).
- `reverse(booking_id, actor)` — returns exactly what was debited to the original lots. If a lot has expired, create a `return_grace` lot expiring in 14 days (configurable per tenant) instead. Idempotent.
- `balance(household_id)` — grouped by eligibility scope + nearest expiry (implements the wp-00 stub).
- `adjust(household_id, lot_id | nil, delta, note, actor)` — admin only, audited.
- Subscriber `order.paid` → grant for package lines. Subscriber `order.refunded` → revoke remaining credits on refunded package lines (only unused ones; report used count back in the refund response via `revocable_for(order_line_id)`).
- Jobs: daily expiry (expire remaining on lapsed lots, emit `credits.expired`); daily `credits.expiring_soon` at 7 days (once per lot).

## Endpoints
- Portal: household balance + lot history.
- Staff: household balance, ledger history, manual adjust, grant complimentary credits.

## Acceptance criteria
- Property test: random sequences of grant/consume/reverse/expire keep the invariant and never produce negative remaining.
- Concurrency: two simultaneous consumes of the last credit → one succeeds.
- Reversal after expiry → grace lot created.
- Isolation + policy tests.

## Out of scope
Deciding whether to reverse (wp-14 + wp-10), pricing (wp-03).
