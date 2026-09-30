# WP-10 — Cancellation & Rebooking Policies

**Phase:** 1 (feeds critical path) · **Hard deps:** wp-00

## Goal
Owners configure cancellation/rebooking rules; a **pure** engine computes the outcome for any cancel/rebook/no-show against the policy snapshot stored on a booking.

## You own
`App.Policies`, controllers `staff/policies/`, portal read endpoint. Migrations prefixed `policies_`.

## Schemas
- **cancellation_policies**: name, `is_default` (one per tenant), `version`, `active`, `rules` (embedded schema, below), `customer_facing_summary` (markdown shown in portal and emails).
- **offering_policy_assignments**: offering → policy (optional override of the default).
- Editing a policy creates a new version; existing bookings keep their snapshot.

## Rules (embedded, validated)
```elixir
%Rules{
  cancellation_tiers: [                      # evaluated in order, first match wins
    %{min_hours_before: 24, credit_outcome: :return, money_refund_pct: 100},
    %{min_hours_before: 12, credit_outcome: :return, money_refund_pct: 50},
    %{min_hours_before: 0,  credit_outcome: :forfeit, money_refund_pct: 0}
  ],
  no_show:  %{credit_outcome: :forfeit, money_refund_pct: 0},
  late_cancel_counts_as_no_show: false,
  rebook: %{allowed: true, min_hours_before: 12, max_rebooks_per_booking: 2, same_offering_only: true},
  provider_cancelled: %{credit_outcome: :return, money_refund_pct: 100}   # when the tenant cancels a session
}
```
Credits are integers, so credit outcomes are `:return | :forfeit` (no partial credits). `money_refund_pct` applies to bookings paid per session.

## Engine (the important part)
```elixir
Policies.Engine.evaluate(snapshot :: map, facts :: %{
  action: :cancel | :rebook | :no_show | :provider_cancel,
  session_starts_at: DateTime.t(), now: DateTime.t(),
  payment_method: :credits | :paid, amount_paid: Money.t() | nil,
  rebook_count: non_neg_integer, target_offering_id: id | nil, source_offering_id: id
}) :: %Outcome{allowed?: boolean, reason: atom | nil, credit_outcome: :return | :forfeit | nil,
               refund_amount: Money.t() | nil, tier_matched: integer | nil}
```
- No DB, no clock reads, no tenant context. All time math in UTC.
- `Policies.snapshot_for(offering_id) :: map` (JSON-serializable, includes policy id + version + summary) — wp-14 stores this on the booking.

## Other
- Subscriber on `tenant.created`: seed a sensible default policy (24 h full return, else forfeit; rebook allowed ≥ 12 h, max 2).
- Portal endpoint: policy summary for an offering (shown before purchase/booking).
- Staff: CRUD, set default, assign to offerings, "simulate" endpoint (given hours-before → outcome) for the admin UI.

## Acceptance criteria
- StreamData property tests: cancelling earlier is never worse than cancelling later; refund never exceeds amount paid; exactly one tier matches; `provider_cancel` always returns credits.
- Boundary tests at exactly `min_hours_before`.
- Rules validation rejects unordered/overlapping tiers and pct outside 0..100.
- Isolation + policy tests.

## Out of scope
Applying outcomes (wp-14 does that), UI (fe-01).
