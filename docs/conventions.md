# SportsCoachBookings — Engineering Conventions

Status: living document, owned by wp-00. These are the architecture rules from
`00-shared-context.md` restated as actionable engineering conventions. Where a
rule and this document disagree, fix this document in the same PR that changes
the rule.

## 0. Toolchain and environments

| Tool | Version / location | Notes |
|---|---|---|
| Elixir | 1.20 (OTP 29) | pinned in `.tool-versions` (`elixir 1.20.4-otp-29`, `erlang 29.1.1`); use `asdf` |
| Postgres | 16 | Docker container named `scb-postgres`; superuser `postgres`/`postgres` |
| App DB role | `scb_app` / `scb_app` | non-superuser, non-owner; the app always connects as this role (see §1) |
| pnpm | via corepack | workspaces: `apps/admin`, `apps/portal`, `packages/ui`, `packages/api-client`, `packages/mocks` |
| Node | pinned by corepack / `.nvmrc` if present | |

Never run migrations as `postgres` for anything other than creating/owning the
database and the `scb_app` role; the application role must remain unable to
bypass RLS.

## 1. Tenancy and Row Level Security (RLS)

1. Every tenant-owned table has `tenant_id uuid not null`, an index on
   `tenant_id`, RLS **enabled and forced**, and a policy
   `USING (tenant_id = current_setting('app.tenant_id', true)::uuid)`
   `WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)`.
2. Platforms tables (`tenants`, `tenant_domains`, `webhook_events`, `oban_*`) have
   no `tenant_id` and no RLS.
3. The tenant is resolved **only** from the request host by
   `SportsCoachBookingsWeb.Plugs.ResolveTenant`. Never read a tenant from a body,
   query param, or header.
4. The process-level tenant lives in `SportsCoachBookings.Core.TenantContext`
   (`put_tenant/1`, `get_tenant/0`, `get_tenant_id/0`, `with_tenant/2`, `clear/0`).
5. All tenant-scoped reads/writes run through a context's public API. Cross-context
   access is never a `Repo` call on another context's schema.

### 1.1 `Repo.prepare_query/3` guard

`SportsCoachBookings.Repo.prepare_query/3` raises
`SportsCoachBookings.Core.MissingTenantError` when a query touches a schema that
`use`s `SportsCoachBookings.Core.TenantSchema` while no tenant is in context. The
only way around it is an explicit `skip_tenant: true`, which is reserved for
platform queries and must be justified in review.

### 1.2 The GUC and the transaction rule (**important**)

The app repo does **not** override `Ecto.Repo.transaction/2`. A bare
`Repo.transaction/2` therefore does **not** set `app.tenant_id`, so RLS does not
apply and a query can silently read or write across tenants. Tenant-scoped
operations must run inside `SportsCoachBookings.Repo.with_tenant_tx/2`, which
sets `app.tenant_id` for the transaction (via
`set_config('app.tenant_id', $1, true)`) before running the function or
`Ecto.Multi`.

```elixir
alias SportsCoachBookings.Repo
alias SportsCoachBookings.Events

# The tenant is already in the process context (ResolveTenant / put_tenant/1).
Repo.with_tenant_tx(fn ->
  # app.tenant_id is set for this transaction; RLS applies to every statement.
  {:ok, booking} = Bookings.insert_confirmed(attrs)
  Events.publish("booking.created", %{booking_id: booking.id, tenant_id: booking.tenant_id})
  {:ok, booking}
end)
```

```elixir
# Ecto.Multi form
Repo.with_tenant_tx(
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:booking, Booking.changeset(%Booking{}, attrs))
  |> Ecto.Multi.run(:event, fn _repo, %{booking: booking} ->
    Events.publish("booking.created", %{booking_id: booking.id, tenant_id: booking.tenant_id})
  end)
)
```

Rules:

- Any write to a tenant-owned table **must** be inside `with_tenant_tx/2` (or a
  transaction that has already set the GUC). This includes tenant-scoped reads
  that must be covered by RLS rather than only by Ecto scoping.
- Nested `Repo.transaction/2` calls inside `with_tenant_tx/2` inherit the
  transaction-local GUC (they become savepoints); do not clear or reset it.
- If you call `Repo.transaction/2` directly outside `with_tenant_tx/2`, you must
  call `Repo.set_tenant_guc(TenantContext.get_tenant_id())` as the first
  statement, or the operation is not tenant-safe. Prefer `with_tenant_tx/2`.
- Tests using the SQL Sandbox assert isolation both through Ecto and through raw
  SQL (`SportsCoachBookings.TenantIsolation.assert_tenant_isolated/2`); raw SQL
  proves the RLS policy, not just Ecto scoping.

### 1.3 Migration helper for tenant tables

Create tenant-owned tables with `SportsCoachBookings.Core.Migration.tenant_table/3`
(or an equivalent explicit RLS setup). It adds the UUID PK, `tenant_id` FK,
`(tenant_id)` index, timestamps, `ENABLE`/`FORCE ROW LEVEL SECURITY`, and the
isolation policy.

```elixir
defmodule SportsCoachBookings.Repo.Migrations.CatalogCreateVenues do
  use Ecto.Migration
  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :venues do
      add :name, :string, null: false
      add :timezone, :string, null: false
      add :map_url, :string
      add :active, :boolean, null: false, default: true
    end

    create unique_index(:venues, [:tenant_id, :slug])
  end
end
```

### 1.4 Non-superuser application role

RLS is bypassed by superusers and by roles with `BYPASSRLS`, even with
`FORCE ROW LEVEL SECURITY`. The application connects as `scb_app`, a
non-superuser role that does not own the tables. Migrations run as the **same**
`scb_app` role (which is why `FORCE ROW LEVEL SECURITY` matters: the policy
applies to the table owner too). Preparation:

```sql
-- run once as the postgres superuser
CREATE ROLE scb_app LOGIN PASSWORD 'scb_app' NOSUPERUSER NOBYPASSRLS;
-- grant CRUD on the database/objects; never grant ownership to scb_app blindly
```

A security test (wp-19) asserts every tenant-owned table has RLS enabled, forced,
and a policy.

## 2. Context boundaries

- One directory per context under `lib/sports_coach_bookings/<context>/`, owned
  by one WP (see the ownership table in `00-shared-context.md`).
- A context only reads/writes its own tables. Cross-context needs go through the
  other context's public functions or through domain events.
- No `Repo` calls on another context's schemas. `prepare_query` plus code review
  are the enforcement backstops.
- Adding a column to another context's table requires an RFC
  (`docs/rfcs/YYYYMMDD-<slug>.md`). New cross-context foreign keys require an
  RFC too; see `docs/erd.md` for the default list of uuid-only cross-context
  references.
- Public context functions carry `@doc` and `@spec`.

## 3. Domain events and the transactional outbox

- Publish with `SportsCoachBookings.Events.publish(name, payload)` **inside the
  same DB transaction** as the state change. It inserts an Oban job on the
  `:events` queue in that transaction (outbox): the event exists if and only if
  the transaction commits.
- Payloads carry identifiers plus `tenant_id`, never structs, and must be
  JSON-serialisable. `Events.publish/2` stringifies keys and values.
- Subscribers implement `SportsCoachBookings.Events.Subscriber`
  (`handle_event(name, payload)`) and are registered in
  `config :sports_coach_bookings, :event_subscribers`, keyed by event name.
- Delivery is **at-least-once**. Every subscriber must be idempotent (invariant
  6: replaying a webhook or event never double-grants, double-fulfils, or
  double-charges).
- New events are added to the catalog in `00-shared-context.md` via an RFC before
  use.

## 4. Oban and `TenantWorker`

- Oban is the only background-job system. Queues are configured in
  `config/config.exs` (`default`, `events`, `mailers`, ...).
- Every tenant-scoped worker `use SportsCoachBookings.Core.TenantWorker,
  queue: :...` and implements `perform_with_tenant/1` instead of `perform/1`.
- Job args **must** include `tenant_id`. `TenantWorker` restores tenant context
  (via `TenantContext.with_tenant/2`) before `perform_with_tenant/1` runs; a job
  without `tenant_id` returns `{:error, {:missing_tenant_id, args}}`.
- Jobs are idempotent and safe to retry; use unique jobs / idempotency keys where
  duplicates would double-charge or double-send.

## 5. Authorization and policies

- Each context has `<Context>.Policy` implementing
  `SportsCoachBookings.Core.Policy`:
  `authorize(actor, action, resource) :: :ok | {:error, :forbidden}`.
- `use SportsCoachBookings.Core.Policy` gives a deny-by-default
  `authorize/3`; every context replaces it with explicit clauses for owner,
  admin, coach, customer, and anonymous (`nil`).
- Controllers call the policy **before** any context function.
- Actors:
  `%SportsCoachBookings.Core.StaffActor{membership}`
  (`staff_user_id`, membership role/tenant), or
  `%SportsCoachBookings.Core.CustomerActor{customer_user_id, household}`.
- Policy tests cover the full actor matrix for every action. Never rely on the
  frontend to hide an action.

## 6. Audit

- Call `SportsCoachBookings.Core.Audit.record(actor, action, resource, metadata)`
  for every admin write, every medical-data read, every refund/adjustment, and
  every role change.
- It writes to `audit_events` (tenant-owned, append-only) inside the same
  transaction as the change it describes. `action` is dotted snake_case
  (`"staff.role_changed"`).
- `metadata` is JSON and must never contain secrets or raw medical values.

## 7. Money

- Use `SportsCoachBookings.Core.Money`: an integer **minor-unit** amount plus an
  ISO-4217 currency. Never floats.
- Tenants have exactly one currency (`tenants.currency`, default `CAD`), locked
  after the first paid order. `orders.currency` snapshots it per order.
- Arithmetic requires matching currencies and raises otherwise.
  `Money.apply_bps/2` and `Money.percent/2` round half-up to the minor unit.
- Pricing (`Catalog.Pricing.price_lines/3`) rounds per line, half-up, and applies
  tax to the discounted amount.

## 8. Time

- Store `utc_datetime_usec`. Tenants and venues have IANA timezones.
- API returns ISO-8601 UTC; the frontend renders in the venue timezone.
- Recurrence ("Tuesdays 17:00 America/Halifax") must stay at 17:00 local across
  DST changes. All policy-engine time math is in UTC and reads no clock (the
  clock is injected as `now`).

## 9. IDs

- UUIDv7 primary keys, generated in Elixir by
  `SportsCoachBookings.Core.Types.UUIDv7`; schemas get this via
  `SportsCoachBookings.Core.Schema`.
- Human-readable identifiers (for example order numbers `A-000123`) are separate
  columns with per-tenant uniqueness.

## 10. Errors (JSON shape)

Every error response uses:

```json
{ "error": { "code": "snake_case", "message": "…", "details": { "…": "…" } } }
```

- Codes are snake_case and stable (e.g. `session_full`, `waivers_required`,
  `player_conflict`, `insufficient_credits`, `too_late`, `forbidden`,
  `tenant_not_found`).
- Changeset errors map to `422` with `details.fields`.
- `FallbackController` and `ErrorJSON` render this envelope; context/engine
  errors are translated to it at the controller boundary.

## 11. Cursor pagination

- `SportsCoachBookings.Core.Pagination` provides the helper.
- Requests: `?cursor=…&limit=…`. Responses: `{ "data": [ … ], "next_cursor": … }`.
- Cursors are opaque URL-safe keyset tokens over `(inserted_at, id)`, ordered
  newest-first. Default limit 25, max 100.

## 12. OpenAPI

- Every endpoint is documented with `open_api_spex`, tagged `platform`, `staff`,
  or `portal`.
- Regenerate `docs/openapi.json` (`mix app.openapi.export`) and the TypeScript
  client/MSW handlers (`pnpm gen:api`) in the same PR. CI fails on drift.

## 13. Migrations

- Filename: `YYYYMMDDHHMMSS_<context>_<change>.exs`, generated with
  `mix ecto.gen.migration <context>_<change>` (timestamps use
  `:utc_datetime_usec`). Migration module names are
  `SportsCoachBookings.Repo.Migrations.<CamelCase>`.
- `<context>` is the owning context, e.g. `catalog_create_offerings`,
  `bookings_create_bookings`, `core_add_tenant_settings`.
- Tenant-owned tables must be created with
  `SportsCoachBookings.Core.Migration.tenant_table/3` so RLS is enabled and
  forced. See §1.3.
- Migrations run as `scb_app`. New tenant-owned tables must be reachable by that
  role; grant the needed privileges as part of deployment, not by making the role
  a superuser or the table owner.
- Append-only tables (`audit_events`, `credit_ledger_entries`,
  `stock_movements`, `booking_events`) revoke `UPDATE`/`DELETE` for `scb_app`
  (or enforce immutability with a trigger). `credit_ledger_entries` and
  `stock_movements` additionally have a reconciliation test.

## 14. Branch naming

- WP work: `wp-<nn>/<short-slug>`, e.g. `wp-14/booking-engine`,
  `wp-03/pricing-rounding`.
- Non-WP work: `feat/<short-slug>`, `fix/<short-slug>`, `chore/<short-slug>`,
  `docs/<short-slug>`.
- Keep one WP per branch where possible; cross-context changes need an RFC first.

## 15. Commit and PR checklist

Every PR:

- [ ] Branch name follows §14; commits are focused and messages describe intent.
- [ ] Tenant-scoped writes go through `Repo.with_tenant_tx/2` (or set the GUC).
- [ ] New tenant-owned tables use `tenant_table/3`, with RLS enabled and forced.
- [ ] Context boundaries respected; no cross-context `Repo` calls or new
      cross-context FKs without an RFC.
- [ ] Events published inside the transaction; subscribers idempotent and
      registered in config; event present in the catalog.
- [ ] Policies deny by default and have the full actor-matrix tests.
- [ ] Audit calls for admin writes, medical reads, refunds/adjustments, role
      changes.
- [ ] Money in integer minor units; times in `utc_datetime_usec`.
- [ ] `mix precommit` green (see §16).
- [ ] `docs/openapi.json` exported and TS client regenerated (`pnpm gen:api`),
      compiling; no drift.
- [ ] Seeds updated so `mix setup` yields usable demo data; `TODO`s linked to an
      issue.
- [ ] Docs updated (`docs/erd.md`, `docs/conventions.md`, or an RFC) when
      schema/architecture changes.

## 16. Definition of done

All backend WPs:

- Public context API has `@doc` and `@spec`; dialyzer clean.
- Policy tests for owner / admin / coach / customer / anonymous on every action.
- Tenant isolation test for every schema owned.
- OpenAPI updated; TS client regenerated and compiling.
- Published events are in the catalog and have a publication test.
- Seeds produce a usable demo tenant with the WP's data.
- No `TODO` without a linked issue.

CI gates (all must pass):

- Backend: `mix format --check-formatted`, `mix credo --strict`, dialyzer,
  `sobelow`, `mix test`, OpenAPI drift check (`mix app.openapi.export` then
  `git diff --exit-code`).
- Frontend: `pnpm -r typecheck`, `pnpm -r lint`, `pnpm -r test`.
- Security (wp-19): authorization matrix, IDOR sweep, RLS verification,
  `mix hex.audit`, `mix deps.audit`, `pnpm audit`.

## 17. Commands

Backend (from `backend/`):

| Command | Purpose |
|---|---|
| `mix setup` | deps, create/migrate DB, seed the `demo` tenant, build assets |
| `mix ecto.migrate` | apply migrations |
| `mix app.openapi.export` | write `docs/openapi.json` |
| `mix precommit` | `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `test` |

Frontend (from the repo root, pnpm workspace):

| Command | Purpose |
|---|---|
| `pnpm gen:api` | regenerate the typed client + MSW handlers from `docs/openapi.json` (orval) |
| `pnpm -r typecheck` | TypeScript across all workspaces |
| `pnpm -r lint` | ESLint across all workspaces |
| `pnpm -r test` | Vitest across all workspaces |
