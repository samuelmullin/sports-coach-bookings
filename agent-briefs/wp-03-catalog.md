# WP-03 — Catalog: Venues, Offerings, Packages, Discounts, Tax Rates

**Phase:** 1 (critical path — prioritize) · **Hard deps:** wp-00

## Goal
Owners/admins define what they sell and where it happens.

## You own
`App.Catalog`, controllers `staff/catalog/`, `portal/catalog/`. Migrations prefixed `catalog_`.

## Schemas
- **venues**: name, address fields, `timezone` (defaults to tenant's), notes, map URL, `active`.
- **offerings** (class types): name, slug, description, `format` (`private|semi_private|group`), `min_age`, `max_age` (nullable), `duration_minutes`, `default_capacity`, `credit_cost` (int, default 1), `drop_in_price` (Money, nullable = credits only), `taxable`, `bookable_until_minutes_before` (default 60), `bookable_from_days_ahead` (nullable), `active`, `position`, `image_key`.
- **packages**: name, description, `credit_quantity`, `eligible_offering_ids` (join table `package_offerings`; empty = all offerings), `validity_days` (nullable = no expiry), `price` (Money), `taxable`, `per_household_limit` (nullable), `active`, `visible_in_portal`.
- **discounts**: `code` (nullable; null = automatic), `kind` (`percent|fixed`), `value`, `applies_to` (`all|packages|drop_ins|products`), optional target IDs (join table), `starts_at`, `ends_at`, `max_redemptions`, `per_household_limit`, `min_subtotal`, `active`. `discount_redemptions` is written by wp-13 via your `record_redemption/3`.
- **tax_rates** (pending decision #2): `name` (e.g. "HST"), `rate_bps`, `active`. MVP: one active rate applied to taxable lines.

## Public functions (others depend on these — publish signatures early)
- `get_offering!/1`, `list_offerings/1` (filters: active, format, age), `get_package!/1`, `list_packages/1`
- `package_eligible_offering_ids(package_id) :: :all | [id]`
- `Catalog.Pricing.price_lines(lines, discount_code, household_id) :: {:ok, %{lines, discount, subtotal, discount_total, tax_total, total}} | {:error, reason}`
  - Pure over inputs + current catalog rows. `lines` are `%{type: :package | :drop_in | :product, ref_id, unit_price, quantity, taxable}` (products priced by wp-08 and passed in).
  - Discount errors: `invalid_code`, `expired`, `exhausted`, `not_applicable`, `min_subtotal_not_met`, `household_limit_reached`.
  - Rounding: compute per line, round half-up to minor unit, tax on discounted amount.
- `record_redemption(discount_id, household_id, order_id)`

## Endpoints
- Staff CRUD for all schemas (owner/admin; coaches read-only on venues/offerings).
- Reorder offerings/packages. Archive instead of delete when referenced.
- Portal (public, no login): list active offerings, visible packages, venues.
- Staff: "validate discount" preview endpoint.

## Acceptance criteria
- Property tests for `price_lines`: totals never negative, discount never exceeds eligible subtotal, sum of lines = total.
- Archiving an offering used by a package keeps the package valid but hides the offering in the portal.
- Isolation + policy tests. Seeds: 2 venues, 4 offerings (private, semi-private, 2 group age bands), 3 packages, 1 code discount.

## Out of scope
Sessions/scheduling (wp-11), cart/checkout (wp-13), product/merch (wp-08).
