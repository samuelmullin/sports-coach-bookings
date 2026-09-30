# AGENTS.md — SportsCoachBookings backend

Read `../00-shared-context.md` and `../docs/conventions.md` first. This file is
only the quick-reference for working in `backend/`.

## What this is

A Phoenix **JSON API only** (no LiveView, no server-rendered product UI), Ecto,
Postgres 16. The product UI is a separate React app under `../frontend/`.

## Commands

```bash
mix setup                 # deps, ecto.setup (create/migrate/seeds), assets.build
mix ecto.migrate
mix test                  # runs ecto.create/migrate then ExUnit
mix format
mix precommit             # compile --warnings-as-errors, format, credo --strict, test
mix app.openapi.export    # writes ../docs/openapi.json
```

Toolchain is managed by asdf (see `../.tool-versions`): Elixir 1.20 / OTP 29.
Postgres runs in Docker (`scb-postgres`, `postgres`/`postgres`). The application
connects as the non-superuser role `scb_app`/`scb_app`; RLS is bypassed by
superusers, so never point the app at the `postgres` role.

## Rules that bite if ignored

- **Tenancy.** Every tenant-owned table is created with
  `SportsCoachBookings.Core.Migration.tenant_table/3` and every tenant-owned
  schema `use SportsCoachBookings.Core.TenantSchema` with a `tenant_id` field.
  Tenant-scoped writes run inside `Repo.with_tenant_tx/2` so `app.tenant_id` is
  set for the transaction and RLS applies. `Repo.prepare_query/3` raises
  `MissingTenantError` for tenant-scoped queries with no tenant in context.
- **No cross-context Repo calls.** A context only touches its own schemas; use
  the other context's public functions or domain events.
- **Events** are published with `SportsCoachBookings.Events.publish/2` inside the
  same transaction as the state change. Subscribers are Oban workers; payloads
  are IDs + `tenant_id`, never structs, and must be idempotent.
- **Money** is `SportsCoachBookings.Core.Money` (integer minor units). Never
  floats.
- **Time** is `utc_datetime_usec`; render in the venue timezone on the client.
- **Errors** use the envelope
  `{"error": {"code", "message", "details"}}` via `FallbackController`.
- **Pagination** is cursor-based: `?cursor=…&limit=…` →
  `{"data": [...], "next_cursor": …}` via `Core.Pagination`.
- Every endpoint is documented with `open_api_spex`; regenerate
  `docs/openapi.json` (and the TS client) in the same change.

## Elixir / Ecto

- Do not use index access on lists; use `Enum.at/2`.
- Access struct fields directly (`struct.field`), not `struct[:field]`.
- Every setup step and test uses `start_supervised!/1`; avoid `Process.sleep/1`.
- Generate migrations with `mix ecto.gen.migration <context>_<change>` and do not
  rename the timestamp prefix.

## Testing

- Backend tests use `SportsCoachBookings.DataCase` / `ConnCase`.
- Add a tenant-isolation test for every schema you own using
  `assert_tenant_isolated/3` (it checks both Ecto scoping and raw-SQL RLS).
- Add a policy test for owner / admin / coach / customer / anonymous on every
  action.
- `insert(:tenant)` and other factories live in
  `test/support/factory.ex`; add factories for your schemas there.
