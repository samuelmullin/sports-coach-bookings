# WP-13 — Commerce: Cart, Orders, Checkout

**Phase:** 2 · **Hard deps:** wp-03, wp-04, wp-08, wp-12 · **Soft deps:** wp-14

## Goal
One order model for everything customers pay for — packages, pay-per-session bookings, and merch — with discounts, tax, provider checkout, and refunds.

## You own
`App.Commerce`, controllers `portal/cart/`, `portal/orders/`, `staff/orders/`. Migrations prefixed `commerce_`.

## Schemas
- **carts**: household, `discount_code`, `expires_at`.
- **cart_lines**: `type` (`package|product|drop_in`), `ref_id` (package id / variant id / **booking hold id** for drop-ins), `quantity`.
- **orders**: `number` (per-tenant sequence, e.g. `A-000123`), household, placed_by (customer user or staff), `status` (`pending_payment|paid|expired|cancelled|refunded|partially_refunded`), `currency`, `subtotal`, `discount_total`, `tax_total`, `total`, `discount_id`, `expires_at`, `paid_at`.
- **order_lines**: type, ref_id, `description` (snapshot), `unit_price`, `quantity`, `discount_amount`, `tax_amount`, `line_total`, `taxable`.

## Flow
1. Cart ops: add/remove/update lines; drop-in lines are created by wp-14 (`Bookings.create_hold/…` → returns hold id → `Commerce.add_drop_in(hold_id)`).
2. `POST /api/portal/checkout`: require confirmed customer (`Customers.require_confirmed/1`); re-price via `Catalog.Pricing.price_lines/3` (products priced from `Inventory.price_and_availability/1`); enforce `per_household_limit` on packages; `Inventory.reserve/2`; create order `pending_payment` with 30-min expiry; `Payments.create_checkout/1`; return redirect URL.
3. Zero-total orders (100 % discount / comp) skip the provider and go straight to paid.
4. Subscriber `payment.succeeded` → order `paid`, `Catalog.record_redemption/3`, publish `order.paid` with line summaries (wp-12 grants credits, wp-08 commits stock, wp-14 confirms holds, wp-16 sends receipt). Idempotent.
5. Expiry job + `payment.failed` → order `expired`, publish `order.expired` (releases stock + booking holds).

## Refunds (owner/admin)
- Full or per-line partial. For package lines, show `Credits.revocable_for/1` and block refunding a line whose credits were used unless `force: true` (audited).
- Calls `Payments.refund/4`; on `payment.refunded` → update status, publish `order.refunded` with the refunded lines.
- Staff can also create an order on behalf of a household (e.g. cash/e-transfer at the field) marked `paid` with `payment_method: offline` — audited.

## Public API (used by wp-14)
- `Commerce.add_drop_in(household_id, hold_id)` → adds the held booking as a cart line priced at the offering's `drop_in_price`.
- `Commerce.refund_line(order_line_id, Money.t(), reason, actor)` → partial refund used by policy-driven cancellations; idempotent per `(order_line_id, booking_id)`.
- `Commerce.any_paid_orders?/0` (used by wp-01 to lock currency).

## Endpoints
- Portal: cart CRUD, apply/remove discount, price preview, checkout, order history, order detail + receipt.
- Staff: order list (filters: status, date, household, type), detail, refund, offline order.

## Acceptance criteria
- End-to-end with Fake provider: package + product + drop-in in one order → paid → credits granted, stock sold, hold confirmed, exactly once under event replay.
- Expired checkout releases stock and holds.
- Money totals always reconcile (sum of line totals = order total).
- Isolation + policy tests.

## Out of scope
Saved payment methods, subscriptions/memberships, shipping, invoices for businesses.
