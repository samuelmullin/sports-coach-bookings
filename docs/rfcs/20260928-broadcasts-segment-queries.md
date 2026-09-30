# RFC: Efficient cross-context segment queries for broadcasts

Date: 2026-09-28
Owner: wp-17 (Broadcasts)
Status: proposed (build-to-seam; current wp-17 composes existing public functions)

## Context

wp-17 resolves a broadcast segment to household ids. Segments combine (AND/OR):

- all households
- households with a confirmed booking in session(s) / offering(s) / venue / date range
- households with players in an age range
- households with a credit balance / lots expiring before a date
- households who purchased a package

Per the architecture rules, `Notifications.Broadcasts` must not read another
context's tables. The current implementation
(`SportsCoachBookings.Notifications.Broadcasts.Segments`) already respects that:
it resolves every condition through the owning context's **existing** public
query functions:

- `Customers.list_households/1` + `Customers.list_household_members/1`
- `Scheduling.list_sessions/1` -> `Bookings.page_bookings/2`
- `Players.search/1` + `Players.age_on/2`
- `Credits.balance/1` / `Credits.list_lots/1` (per household)
- `Commerce.page_orders/2` (preloading order lines)

## Problem

The composition is correct but not efficient: credits and package conditions are
`O(households)` and booking/offering/venue/date conditions page through all
bookings for the status. That is acceptable for MVP volumes but will not scale.

## Proposal

Add the following *read-only* public query functions to the owning contexts.
Each returns de-duplicated `household_id`s for the tenant in context and runs
inside `Repo.with_tenant_tx/2` like every other read:

- `SportsCoachBookings.Bookings.household_ids_for/1`
  filters: `:status` (default `:confirmed`), `:session_ids`, `:offering_ids`,
  `:venue_id`, `:from`, `:to`.
- `SportsCoachBookings.Players.household_ids_for_age/1`
  filters: `:min`, `:max`, `:include_inactive` (default `false`).
- `SportsCoachBookings.Credits.household_ids_with_balance/1`
  filters: `:min_balance`, `:expiring_before`.
- `SportsCoachBookings.Commerce.household_ids_for_package/1`
  filters: `:package_id`, `:statuses` (default `[:paid]`).

wp-17 would then prefer these functions when exported (via
`function_exported?/3`) and fall back to the current composition otherwise — the
same seam pattern used by `:inventory_order_source`,
`:scheduling_bookings_source`, and `:commerce_booking_hold_source`.

No schema or event changes are required; these are pure read helpers.

## Until implemented

No behaviour changes are needed. The composition is covered by
`test/sports_coach_bookings/notifications/broadcasts_test.exs` (segment
resolution) and returns the same sets these helpers would.
