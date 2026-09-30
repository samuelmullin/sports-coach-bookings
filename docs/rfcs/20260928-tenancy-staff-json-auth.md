# RFC 20260928 — Staff auth: hand-written JSON auth instead of `phx.gen.auth`

**Owner:** wp-01 (Staff). **Status:** implemented.

## Context

WP-01's brief says to generate staff identity with
`mix phx.gen.auth Staff StaffUser staff_users --no-live --binary-id`. This app
was generated `--no-html --no-live`, and the Phoenix 1.8 generator refuses to
run without `phoenix_html`:

```
$ mix phx.gen.auth Staff StaffUser staff_users --no-live --binary-id
** (Mix) mix phx.gen.auth requires phoenix_html
mix phx.gen.auth must be installed into a Phoenix 1.5 app that
contains ecto and html templates.
Apps generated with --no-ecto or --no-html are not supported.
```

It creates no files before failing. The brief explicitly allows
hand-writing the equivalent JSON auth when the generator does not fit.

## Decision

1. Hand-write the auth in `SportsCoachBookings.Staff`, keeping the generated
   semantics: `StaffUser` (global, email + password + `confirmed_at`),
   `StaffUserToken` (hashed opaque tokens), registration, session, confirmation,
   and password-reset flows.
2. Passwords use PBKDF2-HMAC-SHA256 via OTP `:crypto`
   (`SportsCoachBookings.Staff.Password`), so no hashing dependency is added.
   The work factor is `config :sports_coach_bookings, :password_hashing_iterations`
   (lowered in `test.exs`).
3. Auth endpoints are JSON controllers under
   `SportsCoachBookingsWeb.Platform.*`; **no HTML views/templates/LiveViews are
   added**.
4. `/api/staff/*` requires a logged-in staff user with an active membership in
   the tenant resolved from the host, via
   `SportsCoachBookingsWeb.Plugs.StaffActor`.
5. `memberships` gets an additive `FOR SELECT` RLS policy
   `memberships_self_read` keyed on `app.staff_user_id`, so `/api/platform/me`
   can list a user's memberships across tenants on the platform host.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited. The `memberships`
  policy addition is within WP-01's own table.
