# RFC 20260928 — Customers: purchase/booking guard stub

**Owner:** wp-02 (Customers); replaced by wp-13/wp-14. **Status:** temporary stub.

## Context

`Customers.require_confirmed/1` returns `:ok | {:error, :email_unconfirmed}` and
is the guard wp-13 (Commerce) and wp-14 (Bookings) call before a purchase or
booking. Those contexts are not merged, so there is no real purchase path to
exercise the guard end to end.

## Decision

1. `POST /api/portal/account/purchase_guard` (`Portal.Account.PurchaseGuardController`)
   calls `Customers.require_confirmed/1` for the authenticated customer and
   returns `200 {"message":"confirmed"}` or, through `FallbackController`, a
   `403` with code `email_unconfirmed`.
2. This exists only to make the `403 email_unconfirmed` contract verifiable now.
   `FallbackController` maps `:email_unconfirmed -> :forbidden` permanently, so
   wp-13/wp-14 get the correct status for free when they call the context
   function.

## Follow-up (when wp-13/wp-14 merge)

- Delete the stub controller and route; call `Customers.require_confirmed/1` in
  the real checkout/booking guard.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited.
