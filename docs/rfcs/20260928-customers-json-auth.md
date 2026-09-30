# RFC 20260928 — Customer auth: hand-written JSON auth, per-tenant identity

**Owner:** wp-02 (Customers). **Status:** implemented.

## Context

WP-02's brief says to generate customer identity with `phx.gen.auth` into
`App.Customers` (`CustomerUser`, tokens), tenant-scoped. As with wp-01's staff
auth, `mix phx.gen.auth` refuses to run in this `--no-html --no-live` app and no
files are produced before it fails. The brief allows hand-writing the equivalent
JSON auth.

Customer identity differs from staff identity in one crucial way: it is **per
tenant**, not global. The same email at two tenants is two independent accounts.

## Decision

1. Hand-write the auth in `SportsCoachBookings.Customers`, keeping the generated
   semantics: `CustomerUser` (email + password + `confirmed_at`), `CustomerUserToken`
   (hashed opaque tokens for `session | confirm | reset_password | change_email`),
   plus registration, session, confirmation, password-reset, and email-change flows.
2. `customer_users` and `customer_users_tokens` are **tenant-owned** tables
   (`tenant_id` + RLS, created with `Core.Migration.tenant_table/3`). The unique
   index is `(tenant_id, email)` with `citext`, implementing
   `(tenant_id, lower(email))`.
3. Passwords reuse `SportsCoachBookings.Staff.Password` (PBKDF2-HMAC-SHA256 via
   OTP `:crypto`); no new dependency. Registration also stores the accepted
   terms/privacy **version + timestamp**.
4. Email confirmation is required before purchase/booking but **not** before
   login. `Customers.require_confirmed/1` returns `:ok | {:error, :email_unconfirmed}`;
   wp-13/wp-14 call it in their guard path and the web layer maps it to `403`
   with code `email_unconfirmed`.
5. Registration/login/password-reset run on a tenant host, so the tenant is
   resolved from the host first (`ResolveTenant`); the account created belongs to
   that tenant only.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited.
