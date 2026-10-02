# AGENTS.md — SportsCoachBookings repository overview

This repository contains a substantial MVP implementation, not an unstarted set
of work packages. The root `README.md` describes the original execution plan (it
now carries a status banner and an up-to-date checklist) and RFC status labels
were reconciled on 2026-10-01; still inspect the code and tests before trusting
any checklist as project status.

## Read first

1. `00-shared-context.md` — product model, invariants, context ownership.
2. `docs/conventions.md` — tenancy/RLS, transactions, events, policies, money,
   time, errors, pagination, and testing rules.
3. `backend/AGENTS.md` before changing backend code.
4. `docs/erd.md`, `docs/security-review.md`, and `docs/ops.md` as relevant.

## What exists

- `backend/`: Phoenix 1.8 JSON API, Ecto/Postgres, Oban, Swoosh, OpenAPI.
  Tenant/staff/customer auth, catalog, scheduling, reservations, bookings,
  commerce/Stripe, credits, players, waivers, inventory, feedback,
  notifications/broadcasts, security checks, and ops endpoints are implemented.
- `frontend/apps/admin`: owner/admin/coach React SPA.
- `frontend/apps/portal`: customer React SPA.
- `frontend/packages/api-client`: Orval-generated API client.
- `frontend/packages/mocks`: generated and custom MSW handlers.
- `frontend/packages/ui`: shared UI components and formatting helpers.
- `docs/openapi.json`: generated API contract (currently about 269 operations).
- Backend journey tests live in `backend/test/e2e`. Browser journeys (Playwright,
  real SPAs + Phoenix + Postgres) live in `e2e/`; see `e2e/README.md`.

## Commands

Infrastructure, from the repository root:

```bash
docker compose up -d postgres rustfs rustfs-init
```

Backend, from `backend/`:

```bash
mix setup
mix test
mix precommit
mix app.openapi.export
```

Frontend, from `frontend/`:

```bash
pnpm install --frozen-lockfile
pnpm typecheck
pnpm lint
pnpm test
pnpm build
pnpm gen:api
```

Browser end-to-end, from `e2e/` (needs the SPAs built, Postgres up, Chrome):

```bash
pnpm install
pnpm test:fresh    # recreate + seed sports_coach_bookings_e2e, then run all journeys
pnpm test          # reuse the existing e2e database
```

If non-interactive shells cannot find Erlang/Elixir, initialise asdf or put the
asdf shims and selected Erlang/Elixir `bin` directories on `PATH`.

Verified on 2026-10-01: frontend typecheck, lint, 180 tests, and production
build pass (no bundle-size warnings; both apps are code-split); backend format,
compile with warnings-as-errors, Credo strict, Dialyzer, Sobelow, and 880 tests
(including 5 properties) pass; the 14 Playwright journeys in `e2e/` pass from a
fresh database and on a re-run.

## Development environment notes

- `config/dev.exs` uses the in-memory `Payments.Providers.Fake` unless
  `STRIPE_SECRET_KEY` is set, links in dev emails point at `demo.localhost:$PORT`,
  `DEV_DB_NAME` overrides the dev database, and `RATE_LIMITING=off` disables the
  limiter (the e2e suite uses all three).
- Production defaults to the shared Postgres rate-limit backend
  (`RATE_LIMIT_BACKEND=ets` opts out) and private waiver PDF storage
  (`S3_PRIVATE_BUCKET`).

## Rules that matter

- The request host determines the tenant. Never accept a tenant id from request
  input as the source of tenancy.
- Tenant-owned work must preserve RLS and run through
  `Repo.with_tenant_tx/2`; use context public APIs across context boundaries.
- Controllers authorize before context calls. Preserve audit requirements for
  admin writes, role changes, refunds/adjustments, and medical-data reads.
- Domain events are transactional and subscribers/workers must be idempotent.
- Money uses integer minor units; timestamps are UTC and rendered in venue time.
- Every endpoint change includes OpenAPI regeneration and a compiling generated
  client. Do not hand-edit generated files under `frontend/packages/*/generated`.
- Preserve unrelated user changes in a dirty worktree.

## Highest-priority gaps

Done since the last review (2026-09-30): booking/convert confirmation guard,
`players.household_id` FK, PIPEDA export/erasure (API + portal UI), waiver PDFs
(real renderer, private store, download endpoints), browser e2e suite, SPA
code-splitting, stale-scaffolding cleanup, shared Postgres rate limiting, and a
batch of defects the e2e suite exposed (see git history / the e2e README).

1. **Production operations are not commissioned.** Fly/S3/DNS/contacts/backup
   drill/error-reporting values are placeholders and need a human: work through
   `docs/launch-checklist.md`.
2. **S3 paths are not yet validated against the production provider.** They
   work against local RustFS (`docker compose up -d rustfs rustfs-init`); CI has
   no S3 server. Validate in staging (checklist §2).
3. **Retention and response policy for PIPEDA requests** need a business
   decision (checklist §6); the code retains orders/payments/ledger by design.
4. **Waiver PDF limits:** text-only layout, no logo/custom fonts; characters
   outside Latin-1 render as `?`. Revisit for non-Latin or branded waivers.
5. **Accessibility/UX audit.** Several defects were found only by driving the
   real UI (unscrollable drawer, `<ul>` with non-`<li>` children, stale-cache
   states). A broader pass is worthwhile: remaining `<ul>` usages, the portal
   nav wrapping at 1280px, and tab/drawer focus order.
6. **Test-environment blind spot.** `put_tenant` sets the RLS GUC for the whole
   sandbox transaction, which hides code that queries tenant tables outside
   `Repo.with_tenant_tx` (this hid a bug where coaches could not see their own
   players). Consider a test helper that runs selected paths without the GUC.
7. **Rate limiter bursts.** Fixed windows allow up to 2x at a boundary; the
   Postgres backend fails open on database errors (documented in the security
   review).

Treat `docs/security-review.md` accepted risks as decisions to re-evaluate at
production-readiness review, not permanent guarantees.
