# WP-14 — Booking Engine

**Phase:** 2 (critical path — assign strongest agent) · **Hard deps:** wp-06, wp-07, wp-10, wp-11, wp-12 · **Soft deps:** wp-13

## Goal
Book, cancel, rebook, and record attendance — correctly under concurrency, with waiver gating, age checks, credits or payment, and policy-driven outcomes.

## You own
`App.Bookings` (including `CoachAccess` implementation), controllers `portal/bookings/`, `staff/bookings/`. Migrations prefixed `bookings_`.

## Schemas
- **bookings**: session, player, household, `booked_by` (customer user or staff), `status` (`held|confirmed|cancelled|attended|no_show`), `payment_method` (`credits|paid|comp`), `credits_used`, `order_line_id` (paid), `policy_snapshot` (map), `rebook_count`, `rebooked_from_id`, `rebooked_to_id`, `hold_expires_at`, `cancelled_at`, `cancel_outcome` (map).
- **booking_events**: booking, `kind`, `actor`, `data`, `inserted_at` (history for staff).
- Unique partial index: one non-cancelled booking per `(session_id, player_id)`.

## Book (`Bookings.book(actor, player_id, session_id, method)`)
In one transaction:
1. Authorize (household manager of the player, or owner/admin).
2. `Scheduling.Seats.lock_session!/1`; check `status == scheduled`, booking window (offering `bookable_until_minutes_before` / `bookable_from_days_ahead`; staff may override with `override: true`, audited).
3. Age eligibility on session date (`Players.age_on/2` vs offering min/max).
4. `Players.bookable?/1` (emergency contact present).
5. `Waivers.missing_for/2` must be empty → else `422 waivers_required` with the list.
6. Player not already booked in an overlapping session → else `422 player_conflict`.
7. Capacity: `booked_count + held_count < capacity` → else `409 session_full`.
8. Method:
   - `:credits` → `Credits.consume/4` (`credit_cost` from offering) → `confirmed`, `booked_count +1`.
   - `:paid` → create `held` booking, `held_count +1`, `hold_expires_at` 30 min; return hold id for `Commerce.add_drop_in/1`.
   - `:comp` (staff only) → confirmed, no charge, audited.
9. Store `Policies.snapshot_for(offering_id)`; insert booking event; publish `booking.created` (for confirmed).

Subscribers: `order.paid` → confirm holds (held→booked counts). `order.expired` → release holds. Job: sweep expired holds.

## Cancel (`Bookings.cancel(actor, booking_id, opts)`)
- `Policies.Engine.evaluate(snapshot, facts)`; apply outcome: `Credits.reverse/2` if `:return`; if paid and `refund_amount > 0` → `Commerce.refund_line/…` (partial refund). Decrement counts. Record `cancel_outcome`. Publish `booking.cancelled`.
- Staff may override the outcome (`outcome: :full_return`), with reason, audited.
- Customer UI needs a **preview**: `GET …/bookings/:id/cancel-preview` returns the outcome without applying it.

## Rebook (`Bookings.rebook(actor, booking_id, target_session_id)`)
- Policy `rebook` rules (allowed, window, max count, same offering). Atomic: lock both sessions in id order; create new confirmed booking carrying the same payment (move credit debits to the new booking without a forfeit; paid bookings move the `order_line_id`); mark old `cancelled` with `rebooked_to_id`. Publish `booking.rebooked`. All book-time checks re-run for the target.

## Attendance
- Staff (owner/admin, or coach assigned to the session) mark `attended` / `no_show` from session start until 7 days after. `no_show` applies the policy `no_show` outcome. Publish events.

## Session cancelled / rescheduled
- `session.cancelled` subscriber → cancel all bookings with the `provider_cancelled` outcome (credits back, full refund for paid).
- `session.rescheduled` → no automatic change; the email (wp-16) offers free cancel/rebook: set a `free_change_until` flag on affected bookings that the engine honours.

## CoachAccess (implement the wp-00 stub)
`player_visible?(staff_actor, player_id)`: true for owner/admin; for coaches, true if the player has a non-cancelled booking in a session the coach is assigned to, from 30 days before to 90 days after the session. Cache per request.

## Endpoints
- Portal: book, list household bookings (upcoming/past), cancel preview, cancel, rebook options (eligible sessions), rebook.
- Staff: book on behalf, session roster, cancel/override, attendance, booking history.

## Acceptance criteria
- **Concurrency:** 50 parallel `book` calls on a capacity-5 session → exactly 5 bookings, counters consistent, no deadlocks (repeat 20×).
- Waiver gate, age gate, duplicate, overlap, window, and full cases each have a test with the documented error code.
- Every policy branch (return/forfeit/partial refund/no-show/provider cancel/rebook limit) exercised end-to-end with ledger assertions.
- Hold expiry releases seats; paid-order confirmation is idempotent.
- Isolation + policy tests.

## Out of scope
Waitlists, recurring "book the whole series" (post-MVP), UI.
