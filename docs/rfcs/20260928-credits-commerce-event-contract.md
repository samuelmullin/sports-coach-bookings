# RFC 20260928 — Credits ↔ Commerce/Bookings contract (wp-12 ↔ wp-13/wp-14)

**Owner:** wp-12 (Credits). **Consumers:** wp-13 (Commerce), wp-14 (Bookings),
wp-16 (notifications).
**Status:** implemented (Credits, Commerce, and Bookings are all merged).

## Context

Credits owns an append-only ledger (`credit_lots` + `credit_ledger_entries`).
Other contexts never read those tables; they call the public `Credits` API or
react to/publish domain events. This RFC pins the exact signatures and event
payloads so wp-13 and wp-14 can be written against stable names.

## Public API wp-14 calls

```elixir
# The household's balance, grouped by eligibility scope. The sum of `amount`
# always equals the sum of the household's ledger entries.
Credits.balance(household_id)
# => [%{offering_id: binary() | :any, amount: integer, nearest_expiry: DateTime.t() | nil}]
#
# Grouping: a lot restricted to one offering is reported under that offering id;
# an unrestricted lot, or one restricted to several offerings, is reported under
# :any. Use `available_for_offering/2` for the exact spendable-on-one-offering number.
Credits.available_for_offering(household_id, offering_id) :: integer()

# Spend credits for a booking. Selects eligible lots (remaining > 0, not expired,
# unrestricted or listing the offering), ordered by soonest expiry then grant
# time, locks them FOR UPDATE, and debits across lots. Idempotent per :booking_id.
# Must run inside the caller's (wp-14) transaction: it uses Repo.with_tenant_tx/2,
# which joins an open transaction as a savepoint.
Credits.consume(household_id, offering_id, amount, booking_id: id, actor: actor, note: note)
# => {:ok, [CreditLedgerEntry.t()]} | {:error, :insufficient_credits}

# Return everything debited for a booking. Appends `reversal` entries; if an
# original lot has expired, a new `return_grace` lot is created instead. Idempotent.
Credits.reverse(booking_id, actor: actor, note: note)
# => {:ok, %{entries: [entry], grace_lots: [lot], amount: integer}}
```

`reverse/2` takes the booking id (the `reference`), not the household — the
household is recovered from the debit entries, and the booking id is the stable
idempotency key.

## Public API wp-13 calls

```elixir
# Idempotent on order_line_id (at most one lot per order line). Publishes
# credits.granted only when a lot is actually created.
Credits.grant(household_id, package_id, order_line_id, quantity: n)
# => {:ok, CreditLot.t()} | {:error, :package_not_found}

# Unused credits still attached to an order line (for a refund quote).
Credits.revocable_for(order_line_id) :: non_neg_integer()

# Revoke the unused portion on a refunded package line (used credits are not
# clawed back). Admin-only / subscriber-driven; audited. Idempotent.
Credits.revoke_unused(actor, order_line_id)
# => {:ok, %{revoked: non_neg_integer()}}
```

## Events wp-12 subscribes to

Registered in `config :sports_coach_bookings, :event_subscribers`:

| Event | Payload (string keys) | Credits behaviour |
|---|---|---|
| `order.paid` | `order_id`, `tenant_id`, `household_id`, `lines: [%{order_line_id, package_id, quantity}]` | `Credits.grant/4` for every line with a `package_id` |
| `order.refunded` | `order_id`, `tenant_id`, `household_id`, `lines: [%{order_line_id}]` | `Credits.revoke_unused/2` for every order line |

Handlers are idempotent (grant keyed on `order_line_id`, revocation keyed on the
lot). WP-13 should include only credit-bearing (package) lines; non-package
lines are ignored.

## Events wp-12 publishes

| Event | When | Payload |
|---|---|---|
| `credits.granted` | a package grant creates a lot | `household_id`, `lot_id`, `amount`, `source`, `tenant_id` |
| `credits.expiring_soon` | a lot enters the expiry window (7 days, once per lot) | `household_id`, `lot_id`, `amount`, `expires_at`, `tenant_id` |
| `credits.expired` | a lapsed lot is swept (daily) | `household_id`, `lot_id`, `amount`, `tenant_id` |

## Append-only ledger vs. the self-FK in the ERD

`docs/erd.md` describes `credit_ledger_entries.reverses_entry_id` as a
self-referential FK. A real self-FK forces Postgres to take a `KEY SHARE` row
lock on the referenced entry during insert, which requires `UPDATE` privilege —
but the append-only rule revokes `UPDATE` from `scb_app`. The column is therefore
a plain `uuid` (no FK constraint); idempotency is still enforced by the partial
unique index on `reverses_entry_id`. This is an implementation-level deviation
inside wp-12's own schema.

## Tenant-configurable return grace

The brief says the `return_grace` lot lifetime is "configurable per tenant". The
`tenants` table (owned by wp-01) has no settings column, so the value is an
app-level config, `config :sports_coach_bookings, :credits_return_grace_days,
14`. Per-tenant configuration needs a `tenants.settings` column added by wp-01.
