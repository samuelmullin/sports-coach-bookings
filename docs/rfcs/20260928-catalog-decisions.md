# RFC 20260928 — Catalog schema decisions (wp-03)

Resolves the `Ambiguities` entries in `docs/erd.md` that wp-03 owns. `docs/erd.md`
is owned by wp-00; this RFC records the choices until wp-00 folds them in.

## Decisions

1. **`discounts.value` encoding (ERD ambiguity #10).** `kind = :percent` stores
   **basis points** (1000 = 10%), matching `tax_rates.rate_bps` and
   `Money.apply_bps/2`. `kind = :fixed` stores minor units. Percent values are
   validated `0..10_000`.
2. **Discount target join (ERD ambiguity #11).** Table name is
   `discount_targets` with a polymorphic `target_type`
   (`:offering | :package | :product`) + `target_id` (uuid, no FK). A line
   matches a target when `line.ref_id == target.target_id` and the line type
   corresponds (`:drop_in` ↔ `:offering`, `:package` ↔ `:package`,
   `:product` ↔ `:product`).
3. **`discount_redemptions` uniqueness (ERD ambiguity #12).** Unique index on
   `(tenant_id, discount_id, order_id)`. `Pricing.record_redemption/3` inserts
   with `on_conflict: :nothing`, so event replays are idempotent.
4. **`tax_rates` one active rate (ERD ambiguity #13).** Enforced with a partial
   unique index `unique(tenant_id) WHERE active`. `Catalog.create_tax_rate/2`
   and `update_tax_rate/3` deactivate the tenant's other rates when the
   created/updated rate is active.
5. **`packages.position` (ERD ambiguity #9).** Added a `position` integer column
   to `packages` (default `0`) so the "reorder packages" endpoint has a stable
   ordering, mirroring `offerings.position`.
6. **`taxable` defaults (ERD ambiguity #8).** Offerings and packages default
   `taxable: false`; seeds opt in explicitly. The pending decision
   (tenant-configured tax rates) is otherwise implemented as specified.

## Not in scope / untouched

- No new domain events are published by the catalog.
- No cross-context foreign keys were added; `discount_redemptions.household_id`
  / `order_id` and `discount_targets.target_id` remain plain uuids.
