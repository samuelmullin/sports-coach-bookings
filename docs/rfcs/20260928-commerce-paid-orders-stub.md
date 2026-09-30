# RFC 20260928 — `Commerce.any_paid_orders?/0` stub

**Owner affected:** wp-13 (Commerce); consumer: wp-01 (Tenancy).
**Status:** temporary stub.

## Context

WP-01 exposes a `currency_locked` flag on tenant settings. The tenant currency
is editable only until the first paid order; wp-13 was to provide
`Commerce.any_paid_orders?/0`. Commerce is not merged.

## Decision

1. `SportsCoachBookings.Commerce.any_paid_orders?/0` is added to the Commerce
   skeleton and reads
   `config :sports_coach_bookings, :commerce_any_paid_orders` (default `false`).
   It is a config read rather than a literal `false` so tests and future code can
   exercise the locked path without editing Commerce.
2. `Tenancy.tenant_settings/1` returns `currency_locked` from this call, and
   `Tenancy.update_settings/2` rejects a currency change with
   `{:error, :currency_locked}` when it is true.

## Follow-up (wp-13)

Replace the config read with a real per-tenant query
(`orders WHERE tenant_id = … AND status = 'paid'`). The function should become
tenant-aware; wp-01 will adapt the call site (it already runs with a tenant in
context).

**Status update (wp-13 merged).** `Commerce.any_paid_orders?/0` now queries
`orders` for a paid/partially-refunded/refunded order in the resolved tenant and
returns `false` when no tenant is in context. The config key
`config :sports_coach_bookings, :commerce_any_paid_orders` is retained as an
explicit test override (wp-01's `tenancy_test.exs` uses it to exercise the
locked path without creating an order). The "no other Commerce code" note below
is superseded: wp-13 now implements the full Commerce context.

## Not changed

- No other Commerce code; no `core/*` or `docs/erd.md`.
