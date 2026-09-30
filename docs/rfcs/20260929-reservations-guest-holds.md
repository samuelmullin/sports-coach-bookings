# RFC 20260929 — Guest reservations / capacity holds

**Owner:** new `Reservations` context (guest booking funnel).
**Status:** implemented.

## Context

An anonymous visitor can select sessions and have their seats held for ~10
minutes before signing up, then convert the reservation into real bookings. The
hold must respect invariant 2 (confirmed + held never exceed capacity), must not
leak seats when it lapses, and conversion must be all-or-nothing.

## Data model

Two tenant-owned tables, created with
`SportsCoachBookings.Core.Migration.tenant_table/3` and `use`-ing
`SportsCoachBookings.Core.TenantSchema` (RLS enabled and forced):

- `reservations`: `token_hash` (SHA-256, never the token), nullable
  `offering_id`, `status` (`active | converted | expired | released`),
  `expires_at`, `last_activity_at`, nullable `household_id` (set on convert),
  `converted_at`. Unique `(tenant_id, token_hash)`; index
  `(tenant_id, status, expires_at)`.
- `reservation_sessions`: `reservation_id` (FK to `reservations`), `session_id`
  (plain uuid, cross-context to Scheduling). Unique
  `(reservation_id, session_id)`; index `session_id`.

All counter changes go through `Scheduling.Seats` (`hold/2`, `release_hold/2`);
this context never writes `booked_count`/`held_count`.

## Token

`create/1` generates an opaque
`Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)` token, returns
it once, and stores only `:crypto.hash(:sha256, token)`. Lookups compare with
`:crypto.hash_equals/2` (constant time). The portal reads it from the
`x-reservation-token` header; the `Reservations.Plugs.ReservationToken` plug
halts `401` when the header is absent and `404` when the token/id does not
match.

## Atomicity and correctness

- **create**: inside one `Repo.with_tenant_tx/2`, `Seats.hold(session_id, 1)`
  per session. If any returns `:capacity_exceeded` or `:not_found`, the whole
  transaction rolls back (`Repo.rollback/1`) so no partial holds remain.
- **extend**: requires `:active` **and** `expires_at >= now` (the sweeper is
  best-effort, so the time check is authoritative). Returns `{:error, :expired}`
  otherwise.
- **release / expire**: release each held seat via `Seats.release_hold/2`, then
  move status to `:released` / `:expired`.
- **convert**: locks the reservation row `FOR UPDATE`, rejects a non-`:active`
  or lapsed reservation with `{:error, :reservation_expired}`, then releases
  **every** guest hold on the reservation (so a reserved session with no
  assignment cannot leak a seat) and calls `Bookings.book/4` per assignment in
  the same transaction. The session row stays locked between release and book,
  so the seat cannot be taken. Any failure rolls the whole transaction back:
  the reservation stays `:active` and the seats stay held. On success it sets
  `household_id`, `status: :converted`, and `converted_at`.

## `expire_due/1`, `skip_tenant`, and the sweeper

The brief asked for a platform sweep with `skip_tenant: true` to find lapsed
reservations across tenants. That does **not** work here: RLS is `ENABLE`d
**and** `FORCE`d on every tenant-owned table, and a query with no
`app.tenant_id` set matches no rows (proved by
`RepoTenancyTest."skip_tenant bypasses the guard (RLS still applies)"`, which
asserts `Repo.all(Event, skip_tenant: true) == []`). `skip_tenant` only bypasses
the `Repo.prepare_query/3` guard, not Postgres RLS.

`expire_due/1` therefore enumerates active tenants from the platform `tenants`
table (no RLS) and sweeps each tenant inside `TenantContext.with_tenant/2`,
exactly like `Credits.DispatchExpiryWorker`. This is equivalent in effect to the
requested scan and keeps RLS intact. `Reservations.SweepWorker` is a plain
`Oban.Worker` (not a `TenantWorker`, because it spans tenants) registered in the
Oban Cron crontab to run every minute. Test config keeps
`testing: :manual, plugins: []`, so the cron entry does not fire in tests.

## API

- `POST /api/portal/reservations` (anonymous) → `201 {id, token, expires_at,
  last_activity_at, sessions, offering_id}`.
- `GET /api/portal/reservations/:id` (token header) → reservation.
- `POST /api/portal/reservations/:id/extend` (token header) → reservation.
- `DELETE /api/portal/reservations/:id` (token header) → `204`.
- `POST /api/portal/reservations/:id/convert` (customer session + token header)
  → `{bookings: [...]}`; `409 reservation_expired` when lapsed.

## Not changed

- No change to `Scheduling.Seats` or `Bookings.book/4` semantics.
- `docs/erd.md` is untouched (per the task).
