# RFC 20260928 — Inventory ↔ Commerce contract (wp-08 ↔ wp-13)

**Owner:** wp-08 (Inventory). **Consumer:** wp-13 (Commerce), wp-16 (notifications).
**Status:** implemented (Commerce calls `Inventory.reserve/2` and publishes the `order.*` events).

## Context

WP-08 sells physical products. Commerce (wp-13) owns `orders` / `order_lines`
and runs the order lifecycle. Inventory cannot read Commerce tables, so the two
contexts meet through a small public API, domain events, and one read seam.

## Public API wp-13 calls

```elixir
# %{variant_id => %{price: %Money{}, available: integer, taxable: boolean, active: boolean}}
Inventory.price_and_availability(variant_ids)

# Atomically reserve every line or none.
# Locks stock_level rows FOR UPDATE in variant_id order to avoid both oversell
# and deadlock. Idempotent per (order_id, variant_id).
Inventory.reserve(order_id, [%{variant_id: id, quantity: n}])
# => {:ok, %{reservations: [...]}}
#  | {:error, {:insufficient_stock, variant_id, available}}
```

## Events wp-08 subscribes to

Registered in `config :sports_coach_bookings, :event_subscribers`:

| Event | Payload (string keys after `Events.publish/2`) | Inventory behaviour |
|---|---|---|
| `order.paid` | `order_id`, `tenant_id`, `lines: [%{order_line_id, variant_id, quantity, pickup_venue_id}]` | Convert reservations to `sold`, create one fulfillment per order line, emit `stock.low` (deduped per variant per day) |
| `order.expired` | `order_id`, `tenant_id` | Release reservations |
| `order.cancelled` | `order_id`, `tenant_id` | Release reservations (alias of `order.expired`) |
| `order.refunded` | `order_id`, `tenant_id` | No automatic restock; admin calls `Inventory.restock_refund/3` |

All handlers are idempotent: replaying an event never double-sells,
double-fulfills, or re-emits a same-day `stock.low`.

### `order.cancelled`

The event catalog lists `order.paid`, `order.refunded`, and `order.expired`
only. WP-08's brief also needs reservation release on cancellation. WP-13 should
either emit `order.expired` for a cancelled order or add `order.cancelled` to
the catalog via its own RFC; the subscriber already handles both names.

### `order.paid` requires `lines`

Fulfillments are keyed by `order_line_id`, which only Commerce knows (the
reservation API takes `variant_id`). WP-13 must include the product order lines
in the payload. If `lines` is absent, reservations are still converted to
`sold`; no fulfillments are created.

## Read seam for portal pickup status

`GET /api/portal/inventory/pickups` needs the caller household's order line ids.
Commerce supplies them via a configurable module:

```elixir
config :sports_coach_bookings,
       :inventory_order_source,
       SportsCoachBookings.Inventory.OrderSource.Stub   # default: returns []
```

WP-13 should implement `order_line_ids_for_household(household_id) :: [id]` and
point the config at `SportsCoachBookings.Commerce` (or a dedicated module).

## Inventory schema notes (beyond `docs/erd.md`)

WP-08 owns these tables; the following are implementation decisions for
ambiguities the ERD flags:

- `stock_movements.actor_type` + `actor_id` (not a single `actor` column),
  mirroring `Core.Audit` (ERD Ambiguity 20). Rows are append-only; the
  `scb_app` role has `UPDATE`/`DELETE` revoked.
- `stock_levels.low_stock_notified_on` (date) dedupes `stock.low` to once per
  variant per day.
- `fulfillments.variant_id` is kept so the portal can render the item without a
  cross-context lookup; it is nilable (`on_delete: :nilify_all`).
- Partial unique indexes on `stock_movements` enforce one
  `reserved`/`released`/`sold` row per `(tenant_id, order_id, variant_id)`.
- `stock_levels` has a partial unique index on `(tenant_id, variant_id)` where
  `venue_id IS NULL` (the MVP single location), plus negative checks.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited.
