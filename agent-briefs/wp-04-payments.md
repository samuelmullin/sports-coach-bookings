# WP-04 — Payments (Provider Abstraction + Stripe Connect)

**Phase:** 1 · **Hard deps:** wp-00

## Goal
Tenants connect a Stripe account; the platform creates hosted checkouts on their behalf, receives webhooks, and issues refunds — all behind a provider-agnostic interface.

## You own
`App.Payments`, `App.Payments.Providers.Stripe`, controllers `staff/payments/`, `webhooks/stripe`. Migrations prefixed `payments_`.

## Provider behaviour (`App.Payments.Provider`, stubbed in wp-00 — finalize it)
```elixir
@callback create_connected_account(tenant) :: {:ok, account_ref} | {:error, term}
@callback onboarding_link(account_ref, return_url, refresh_url) :: {:ok, url}
@callback account_status(account_ref) :: {:ok, %{charges_enabled, payouts_enabled, requirements_due}}
@callback create_checkout(account_ref, CheckoutRequest.t()) :: {:ok, %{session_ref, redirect_url, expires_at}}
@callback refund(account_ref, payment_ref, Money.t(), reason) :: {:ok, refund_ref}
@callback verify_webhook(raw_body, headers) :: {:ok, event} | {:error, :invalid_signature}
@callback normalize_event(event) :: {:ok, NormalizedEvent.t()} | :ignore
```
`CheckoutRequest`: order_id, order_number, customer email, line items (name, unit amount, qty), currency, application fee, success/cancel URLs, metadata (`tenant_id`, `order_id`).

## Schemas
- **provider_accounts**: tenant, `provider`, `account_ref`, `status`, `charges_enabled`, `payouts_enabled`, `requirements` (map), `platform_fee_bps`.
- **payments**: tenant, `provider`, `order_id`, `checkout_ref`, `payment_ref`, `amount`, `status` (`pending|succeeded|failed|expired`), `raw` (map).
- **refunds**: payment, `amount`, `reason`, `refund_ref`, `status`, `actor`.
- **webhook_events**: `provider`, `event_id` (unique), `type`, `payload`, `processed_at`, `error`. **Not tenant-scoped** at insert (tenant resolved from payload/account) — use `skip_tenant` with a comment.

## Stripe specifics
- Express connected accounts, **direct charges** (`Stripe-Account` header), `application_fee_amount` from `platform_fee_bps` (pending decision #1 — keep configurable).
- Hosted Stripe Checkout Sessions (keeps PCI scope at SAQ A). Session expiry 30 min (matches inventory/booking holds).
- One Connect webhook endpoint. Handle: `checkout.session.completed`, `checkout.session.expired`, `payment_intent.payment_failed`, `charge.refunded`, `account.updated`.
- Verify signature on the raw body (custom body reader in the endpoint for this route). Insert `webhook_events` (dedupe on `event_id`), return 200, process in an Oban job.
- Use `stripity_stripe` or a thin `Req` client — your choice, but all Stripe calls go through the adapter only.

## Public API
- `Payments.connect_status/0`, `start_onboarding/1`
- `Payments.create_checkout(order) :: {:ok, redirect_url} | {:error, :provider_not_ready | term}`
- `Payments.refund(payment_id, Money.t(), reason, actor)`
- Publishes `payment.succeeded`, `payment.failed`, `payment.refunded` with `order_id`, `payment_id`, amounts.

## Endpoints
- Staff (owner-only): connect status, start/resume onboarding, set nothing else (fee is platform-controlled).
- `POST /webhooks/stripe`.

## Acceptance criteria
- Full flow in test mode using recorded fixtures + `Fake` provider: onboarding status sync, checkout → `checkout.session.completed` → `payment.succeeded` event exactly once even if the webhook is replayed 3×.
- Refund partial and full; `charge.refunded` reconciles status.
- Checkout refused with `provider_not_ready` when `charges_enabled` is false.
- A second provider could be added by implementing the behaviour alone (document this in `lib/app/payments/README.md`).

## Out of scope
Order/cart logic (wp-13), saved cards, subscriptions, payouts UI.
