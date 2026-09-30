# WP-08 — Inventory & Merchandise

**Phase:** 1 · **Hard deps:** wp-00 · **Soft deps:** wp-13 (order lifecycle events)

## Goal
Tenants sell physical items (branded merch, equipment) with variants and stock tracking; customers pick up items at a venue.

## You own
`App.Inventory`, controllers `staff/inventory/`, `portal/shop/`. Migrations prefixed `inventory_`.

## Schemas
- **products**: name, description, `image_keys` (array), `taxable`, `active`, `visible_in_portal`, `position`.
- **product_variants**: product, `sku` (unique per tenant), `option_values` (map, e.g. `%{"size" => "YM", "colour" => "Navy"}`), `price` (Money), `low_stock_threshold`, `active`.
- **stock_levels**: variant, `on_hand`, `reserved` (single location in MVP; include a nullable `venue_id` column now for later multi-location).
- **stock_movements**: variant, `delta`, `kind` (`received|sold|adjusted|returned|reserved|released`), `order_id`, `actor`, `note`. Ledger — `on_hand` must equal the sum of non-reservation movements (test it).
- **fulfillments**: order line → `status` (`pending|ready_for_pickup|picked_up|cancelled`), `pickup_venue_id`, `picked_up_at`, `picked_up_by` (staff).

## Public API (used by wp-13)
- `Inventory.price_and_availability(variant_ids)` → prices, available (`on_hand - reserved`), taxable.
- `Inventory.reserve(order_id, [%{variant_id, quantity}])` → `{:ok, _}` or `{:error, {:insufficient_stock, variant_id, available}}`. Atomic across lines (lock rows `FOR UPDATE` in a consistent order to avoid deadlocks).
- Subscribers: `order.paid` → convert reservation to `sold`, create fulfillments; `order.expired` / order cancelled → release; `order.refunded` → optional restock (admin choice, not automatic).
- Emit `stock.low` when available ≤ threshold after a sale (dedupe per variant per day).

## Endpoints
- Staff: product/variant CRUD, image uploads (presigned, same pattern as wp-01), stock receive/adjust with reason, movement history, fulfillment queue (mark ready / picked up).
- Portal: list/view products with availability ("in stock", "low stock", "sold out" — don't expose exact counts), pickup status on own orders.

## Acceptance criteria
- Concurrency test: 20 concurrent reservations for a variant with 5 available → exactly 5 succeed.
- Reservation released on `order.expired`; replaying events is idempotent.
- Isolation + policy tests. Seeds: 2 products with size variants.

## Out of scope
Shipping, multi-location stock, purchase orders from suppliers, UI.
