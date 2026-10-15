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
  notifications/broadcasts, hosted marketing sites, security checks, and ops
  endpoints are implemented.
- `frontend/apps/admin`: owner/admin/coach React SPA.
- `frontend/apps/portal`: customer React SPA.
- `frontend/packages/api-client`: Orval-generated API client.
- `frontend/packages/mocks`: generated and custom MSW handlers.
- `frontend/packages/ui`: shared UI components and formatting helpers.
- `docs/openapi.json`: generated API contract (currently about 269 operations).
- Backend journey tests live in `backend/test/e2e`. Browser journeys (Playwright,
  real SPAs + Phoenix + Postgres) live in `e2e/`; see `e2e/README.md`.

## Session booking model

Offerings use independently configured **public** and **private** booking modes;
`format` remains only as a backwards-compatible marketing classification. Each
mode has its own maximum players, players-per-coach ratio, and complete
per-player money/credit tiers. Private capacity is the customer's selected tier
and may exceed the public maximum.

When enabled, a booked customer can invite a previous accepted partner or an
email address. Split-payment invitations reserve one seat for the configured
period (48 hours by default) but cannot start inside that horizon;
organizer-funded seats are still allowed. Empty public occurrences can be
converted to household-exclusive private occurrences, and customers can submit
operator-reviewed requests for new private occurrences. See
`docs/rfcs/20261002-public-private-session-parties.md` before changing these
flows.

## Hosted marketing sites

Each tenant has a structured draft/publish website editor and contact inbox in
the admin SPA. The public portal supplies home, programs/schedule, about,
coaches, testimonials, gallery, sponsors, FAQ, and contact pages while reusing
the live catalog, accounts, and checkout. Images use tenant storage; public
links are restricted to internal or HTTP(S) destinations; robots and sitemaps
are tenant-aware. Read `docs/rfcs/20261003-hosted-marketing-sites.md` before
changing this feature. Custom domains use `tenant_domains` but are manually
commissioned for MVP using `docs/ops.md` §3.1.

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

Verified on 2026-10-03: backend strict compile, format, Credo, and 911 tests pass
(5 properties; the live-storage test is skipped in the ordinary suite); frontend
typecheck, lint, 197 tests, and production build pass. Earlier the same day,
Dialyzer, Sobelow, the live RustFS integration test, all 17 pre-existing
Playwright journeys from a fresh database, and the production container/Unicode
PDF path also passed. The hosted-site Playwright journey also passes from a
fresh database; the complete 18-journey suite has not yet been rerun as one
batch.

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
(branded Unicode browser renderer in production, private store, downloads),
browser e2e plus automated WCAG coverage, SPA code-splitting, stale-scaffolding
cleanup, exact shared sliding-window rate limiting, a live RustFS CI round trip,
an RLS-without-GUC regression helper, and a batch of defects the e2e suite
exposed (see git history / the e2e README).

1. **Production operations are not commissioned.** Fly/S3/DNS/contacts/backup
   drill/error-reporting values are placeholders and need a human: work through
   `docs/launch-checklist.md`.
2. **S3 paths are not yet validated against the production provider.** CI and
   local development exercise RustFS, but provider-specific policy/CORS/CDN
   behaviour must be validated in staging (checklist §2).
3. **Retention and response policy for PIPEDA requests** need a business
   decision (checklist §6); the code retains orders/payments/ledger by design.
4. **Custom domains are manually commissioned.** The host mapping exists, but
   DNS ownership, certificates, cutover, and renewal monitoring follow
   `docs/ops.md` §3.1 until lifecycle automation is justified.
Treat `docs/security-review.md` accepted risks as decisions to re-evaluate at
production-readiness review, not permanent guarantees.
