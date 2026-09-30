# WP-00 — Foundation

**Phase:** 0 (serial, blocks everything) · **Read first:** `00-shared-context.md`

## Goal
Stand up the repo, the multi-tenancy core, the shared building blocks, and the API contract pipeline, so that ten agents can start in parallel without stepping on each other.

## You own
`backend/lib/app/core/**`, `backend/lib/app_web/plugs/**`, `backend/lib/app_web/router.ex` (structure only), `backend/test/support/**`, `frontend/` workspace config, `docs/erd.md`, `docs/conventions.md`, CI config, context skeleton modules for every context.

## Deliverables

### Backend
1. Phoenix app (`--no-html --no-live --binary-id`), Postgres, Oban, Swoosh (Resend adapter; `Swoosh.Adapters.Local` in dev with mailbox preview route).
2. **Tenancy core**
   - `tenants` and `tenant_domains` tables (minimal columns; wp-01 extends via its own migrations).
   - `App.Core.TenantContext`: `put_tenant/1`, `get_tenant!/0`, `with_tenant/2`.
   - `App.Repo` wrapper that runs `SET LOCAL app.tenant_id = $1` at the start of every transaction when a tenant is set. Tenant-scoped reads outside an explicit transaction must also be covered (e.g. `Repo.with_tenant_tx/1` used by a plug for each request, or `prepare_query` + checkout hook — pick one and document it).
   - `Repo.prepare_query/3` guard: raises `App.Core.MissingTenantError` for schemas that `use App.Core.TenantSchema` when no tenant is set and `skip_tenant: true` isn't passed.
   - `App.Core.Migration.tenant_table/2`: creates the table with `tenant_id` FK, composite indexes helper, `ENABLE` + `FORCE ROW LEVEL SECURITY`, and a policy on `tenant_id = current_setting('app.tenant_id', true)::uuid`.
   - The application DB role must not be the table owner or a superuser (otherwise RLS is bypassed). Document the role setup and apply it in dev/test.
   - `AppWeb.Plugs.ResolveTenant` (host → tenant; 404 on unknown; platform host passes through with no tenant).
3. **Shared modules:** `App.Core.Money`, `App.Core.Policy` behaviour + `StaffActor`/`CustomerActor` structs, `App.Core.Audit` (+ `audit_events` table), `App.Core.Events` (publish inside transaction → Oban insert; subscriber registry in config), `App.Core.TenantWorker` macro, standard error JSON view + `FallbackController`, cursor pagination helper, UUIDv7 primary key setup.
4. **Payment behaviour stub:** `App.Payments.Provider` behaviour (callbacks listed in wp-04) and `App.Payments.Providers.Fake` usable in tests.
5. **Cross-context stubs** (implemented later, but the module/function signatures must exist now so callers compile):
   - `App.Bookings.CoachAccess.player_visible?(StaffActor.t(), player_id) :: boolean()` (implemented by wp-14; stub returns `false`).
   - `App.Waivers.missing_for(player_id, offering_id) :: [map()]` (wp-07).
   - `App.Credits.balance(household_id) :: [map()]` (wp-12).
6. **Context skeletons:** empty module + `Policy` module for every context in the ownership table.
7. **OpenAPI:** `open_api_spex` wired into the router with three specs or tagged groups (`platform`, `staff`, `portal`). `mix app.openapi.export` writes `docs/openapi.json`.
8. **Test support:** ExMachina factories for tenant/staff/customer, `assert_tenant_isolated(schema_or_query_fun, factory)`, conn helpers `staff_conn(role)`, `customer_conn()`, `with_host(conn, slug)`.

### Frontend
9. pnpm workspace with `apps/admin`, `apps/portal`, `packages/ui`, `packages/api-client`, `packages/mocks` (empty but building), TypeScript strict, ESLint, Prettier, Vitest.
10. `orval` config generating a typed client + TanStack Query hooks into `packages/api-client` and MSW handlers into `packages/mocks` from `docs/openapi.json`. `pnpm gen:api` script.
11. Phoenix serves built `admin` at `/admin/*` and `portal` at `/*` with SPA fallback (and Vite dev-server proxy config for local dev).

### Docs
12. `docs/erd.md`: full ERD for every schema in the shared context (table, key columns, FKs, owner WP). Other WPs may add columns in their own migrations but not new cross-context FKs without an RFC.
13. `docs/conventions.md`: the rules from the shared context plus migration naming (`YYYYMMDDHHMMSS_<context>_<change>.exs`), branch naming, PR checklist.

### CI
14. `mix format --check`, `credo --strict`, `dialyzer`, `sobelow`, `mix test`, OpenAPI drift check (export + `git diff --exit-code`), `pnpm -r typecheck lint test`.

## Acceptance criteria
- `mix setup` creates a demo tenant `demo`; `curl -H 'Host: demo.localhost' /api/portal/ping` returns the tenant slug; unknown host → 404.
- A test proves RLS blocks a raw SQL `SELECT` across tenants even when Ecto scoping is bypassed.
- A test proves `prepare_query` raises without a tenant.
- An Oban job created with `TenantWorker` runs with tenant context restored.
- `pnpm gen:api` produces a compiling client and MSW handlers.
- CI green.

## Out of scope
Any product feature. Auth flows (wp-01/wp-02). UI components (wp-09).
