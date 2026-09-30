# Payments (WP-04)

Payment provider abstraction plus the Stripe Connect implementation.

## Adding a second provider

A provider is a module implementing `SportsCoachBookings.Payments.Provider`:

```elixir
@callback create_connected_account(tenant) :: {:ok, account_ref} | {:error, term}
@callback onboarding_link(account_ref, return_url, refresh_url) :: {:ok, url}
@callback account_status(account_ref) :: {:ok, %{charges_enabled, payouts_enabled, requirements_due}}
@callback create_checkout(account_ref, CheckoutRequest.t()) :: {:ok, CheckoutSession.t()}
@callback refund(account_ref, payment_ref, Money.t(), reason) :: {:ok, refund_ref}
@callback verify_webhook(raw_body, headers) :: {:ok, event} | {:error, :invalid_signature}
@callback normalize_event(event) :: {:ok, NormalizedEvent.t()} | :ignore
```

**That is the whole contract.** Nothing else in `SportsCoachBookings.Payments`
or the web layer references Stripe directly:

- `SportsCoachBookings.Payments` selects the adapter with
  `config :sports_coach_bookings, :payments_provider` (tests use
  `Payments.Providers.Fake`).
- The controllers, the webhook ingestion, and `Payments.WebhookWorker` consume
  only `NormalizedEvent` structs, never provider payloads.
- A second provider is registered by implementing the behaviour and pointing the
  config at it; no schema, controller, or worker change is required. Add its
  webhook route (if any) next to `POST /webhooks/stripe` and map the provider's
  event types to the normalised atoms in `normalize_event/1`.

The `NormalizedEvent.data` map is the provider-neutral interface between
ingestion and processing; its canonical keys are documented in
`SportsCoachBookings.Payments.NormalizedEvent`.

## Providers

- `Payments.Providers.Fake` — deterministic, network-free; used in tests and
  local development.
- `Payments.Providers.Stripe` — Connect **Express** accounts with **direct
  charges** (`Stripe-Account` header), hosted Checkout Sessions with a 30-minute
  expiry, and `application_fee_amount` from the tenant's `platform_fee_bps`.
  All HTTP goes through the injectable `Payments.Providers.Stripe.Client`
  (`:payments_stripe_client`), so tests never make a real network call.

## Tables

- `provider_accounts`, `payments`, `refunds` — tenant-owned (`tenant_table/3`,
  RLS enabled and forced).
- `payments_webhook_events` — platform-level, deduped on `(provider, event_id)`,
  inserted with `skip_tenant: true`.

## Invariant 6 (replay safety)

A webhook is replayed safely because:

1. `(provider, event_id)` is unique on `payments_webhook_events`, so a replay is
   recorded once (and re-enqueued only while still unprocessed).
2. Status transitions are guarded `UPDATE ... WHERE status <> target`, so
   `payment.succeeded` / `payment.failed` are published only on the first
   transition, even under concurrent jobs.
3. `(tenant_id, refund_ref)` is unique on `refunds`, so `charge.refunded`
   reconciles to a single refund row and publishes `payment.refunded` once.
