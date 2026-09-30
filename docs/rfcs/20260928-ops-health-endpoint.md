# RFC 2026-09-28 — Ops additions to wp-00-owned files

Status: accepted · Owner: wp-20 · Touches: `lib/sports_coach_bookings_web/router.ex`,
`lib/sports_coach_bookings/application.ex`,
`lib/sports_coach_bookings_web/plugs/resolve_tenant.ex`, `config/prod.exs`,
`config/runtime.exs`

## Why

WP-20 (operations & deployment) needs a small number of hooks in files owned by
wp-00 (foundation). Per the ownership rules we record the change here rather than
silently editing core.

## Changes

1. **Health/readiness routes** (`router.ex`):
   `GET /health` (liveness, no DB) and `GET /health/ready` (DB check). Not
   tenant-scoped; required by Fly health checks and the uptime monitor. The
   controller is `SportsCoachBookingsWeb.HealthController`; it declares no
   OpenAPI operations, so it does not appear in `docs/openapi.json` and cannot
   cause OpenAPI drift.
2. **`force_ssl` exclusion for health paths** (`prod.exs`): platforms probe the
   machine directly without `X-Forwarded-Proto`, so redirecting them would fail
   the check. Only `/health` and `/health/ready` are excluded.
3. **Structured JSON log formatter** (`prod.exs`): one JSON object per line using
   `SportsCoachBookings.Logger.Formatter`.
4. **`tenant_id` log metadata** (`resolve_tenant.ex`): sets
   `Logger.metadata(tenant_id: tenant.slug)` after host resolution so every
   request log line is tenant-attributed.
5. **Error-reporter child** (`application.ex`): starts
   `SportsCoachBookings.Ops.ErrorReporter`, which attaches telemetry handlers for
   router exceptions and Oban failures and forwards to a configured reporter.
6. **Production runtime config** (`runtime.exs`): database URL/role guard, Stripe,
   S3, Resend, Cloak key, `REPO_ROOT`, error reporter (see `docs/ops.md`).
7. **Logger metadata allow-list** (`config.exs`): adds `tenant_id` and `error` to
   the configured metadata keys so the tenancy plug and ops error reporter can
   attach them.
8. **Phoenix LiveView compiler** (`mix.exs`): adds
   `compilers: [:phoenix_live_view] ++ Mix.compilers()`. Without it,
   `_build/<env>/phoenix-colocated/.../colocated.css` is never generated, so
   `assets/css/app.css` fails to build (`mix assets.build`, `mix setup`, and the
   Docker image). This was latent because tests do not build assets; it surfaced
   in the wp-20 Docker build. Standard Phoenix 1.8 configuration.

## Impact

Additive and deny-by-default. No schema, event catalog, policy, or tenancy
semantics change. Existing tests are unaffected except for the new coverage added
by wp-20.
