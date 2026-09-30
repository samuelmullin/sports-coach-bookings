# 00 — Shared Context (give to every agent)

## Product

A multi-tenant SaaS for managing bookings of private and small-group coaching sessions (initially youth soccer, but keep the model sport-agnostic).

Each **tenant** is a coaching provider with its own branding, catalog, staff, and customers.

| Actor | Scope | Can do |
|---|---|---|
| Owner | One tenant (via membership) | Everything in the tenant. Owner-only: transfer ownership, delete tenant, payment provider settings. |
| Admin | One tenant | Everything an owner can except owner-only actions. |
| Coach | One tenant | See own sessions, see details of players booked into own sessions, mark attendance, submit feedback. |
| Customer (household manager) | One tenant, one household | Manage household, players, waivers, purchases, bookings. |
| Platform (us) | All tenants | Support tooling only; never exposed in tenant UIs. |

## Stack

- Elixir / Phoenix (JSON API only, no LiveView for product UI), Ecto, Postgres 16+
- Oban for all background work, Swoosh + Resend adapter for email
- TypeScript: React + Vite + TanStack Query + React Router, pnpm workspaces
- OpenAPI via `open_api_spex`; TypeScript client + MSW mocks generated with `orval`
- Stripe (Connect) as the first payment provider behind a provider-agnostic behaviour
- S3-compatible object storage for uploads and generated PDFs
- `cloak_ecto` for field-level encryption

## Repository layout

```
backend/
  lib/app/core/            # Repo, TenantContext, Money, Policy, Audit, Events, Migration helpers  (owned by wp-00)
  lib/app/<context>/       # one directory per context, owned by one WP
  lib/app_web/controllers/{platform,staff,portal,webhooks}/<area>/
  lib/app_web/schemas/<context>/   # OpenApiSpex schemas
  priv/repo/migrations/
  test/app/<context>/  test/support/
frontend/
  apps/admin/     # owners, admins, coaches   → served at {slug}.yourapp.com/admin
  apps/portal/    # customers                 → served at {slug}.yourapp.com/
  packages/ui/  packages/api-client/  packages/mocks/
docs/
  erd.md  conventions.md  openapi.json (generated)  decisions/  rfcs/
```

## Hosts, routing, sessions

| Host / path | Purpose | Auth |
|---|---|---|
| `yourapp.com/signup`, `/api/platform/*` | Tenant signup, staff login, tenant picker | Staff session |
| `{slug}.yourapp.com/admin`, `/api/staff/*` | Admin + coach app | Staff session, cookie on `.yourapp.com` (one login across tenants) + tenant membership check |
| `{slug}.yourapp.com/`, `/api/portal/*` | Customer portal | Customer session, host-only cookie (per tenant) |
| `/webhooks/:provider` | Stripe, Resend | Signature verification |

The tenant is **always** resolved from the host by `AppWeb.Plugs.ResolveTenant`, never from a request body or header.

## Architecture rules

1. **Tenancy.** Every tenant-owned table has `tenant_id uuid not null` and an RLS policy. Create tables with `App.Core.Migration.tenant_table/2`. All tenant-scoped reads/writes happen inside `App.Core.TenantContext` (process-level tenant + `SET LOCAL app.tenant_id` per transaction). `Repo.prepare_query/3` raises on a tenant-scoped query with no tenant set. Platform queries use `skip_tenant: true` and must be justified in review.
2. **Context boundaries.** A context only reads/writes its own tables. Cross-context needs go through the other context's public functions or through domain events. No `Repo` calls on another context's schemas.
3. **Domain events.** `App.Events.publish(name, payload)` inside the same DB transaction as the state change (transactional outbox via Oban). Subscribers are Oban workers registered in config. Payloads contain IDs + `tenant_id`, not structs.
4. **Oban jobs** use the `App.Core.TenantWorker` macro, which requires `tenant_id` in args and restores tenant context before `perform/1`.
5. **Authorization.** Each context has `<Context>.Policy` implementing `App.Core.Policy` → `authorize(actor, action, resource) :: :ok | {:error, :forbidden}`. Controllers call it before any context function. Actors: `%StaffActor{membership}`, `%CustomerActor{customer_user, household}`.
6. **Audit.** `App.Core.Audit.record(actor, action, resource, metadata)` for every admin write, every medical-data read, every refund/adjustment, every role change.
7. **Money.** `App.Core.Money` — integer minor units + ISO currency. Tenants have one currency. Never floats.
8. **Time.** Store `utc_datetime_usec`. Tenants and venues have IANA timezones. API returns ISO-8601 UTC; frontend renders in the venue timezone.
9. **IDs.** UUIDv7 primary keys. Human-readable order numbers are a separate column.
10. **Errors.** JSON shape `{ "error": { "code": "snake_case", "message": "…", "details": {…} } }`. Changeset errors → `422` with `details.fields`.
11. **Pagination.** Cursor-based: `?cursor=…&limit=…` → `{ data: [...], next_cursor }`.
12. **OpenAPI.** Every endpoint documented. Regenerate `docs/openapi.json` and the TS client in the same PR.

## Invariants (every relevant WP must test these)

1. No query returns another tenant's rows (use `assert_tenant_isolated/2` test helper).
2. A session's confirmed + held bookings never exceed capacity, even under concurrent requests.
3. Credit balance always equals the sum of ledger entries. Entries are never updated or deleted, only reversed.
4. A booking cannot be created unless the player has signed every currently-required waiver version.
5. Cancellation outcomes are computed from the policy **snapshot** stored on the booking.
6. Replaying any webhook or event never double-grants, double-fulfills, or double-charges.

## Domain event catalog

| Event | Publisher | Known subscribers |
|---|---|---|
| `tenant.created` | wp-01 | wp-10 (seed default policy), wp-05 |
| `staff.invited`, `staff.joined`, `staff.removed` | wp-01 | wp-16 |
| `customer.registered` | wp-02 | wp-16 |
| `household.member_invited`, `household.member_joined` | wp-02 | wp-16 |
| `player.created`, `player.updated` | wp-06 | — |
| `waiver.published`, `waiver.signed` | wp-07 | wp-16 |
| `payment.succeeded`, `payment.failed`, `payment.refunded` | wp-04 | wp-13 |
| `order.paid`, `order.refunded`, `order.expired` | wp-13 | wp-12, wp-08, wp-14, wp-16 |
| `credits.granted`, `credits.expiring_soon`, `credits.expired` | wp-12 | wp-16 |
| `session.cancelled`, `session.rescheduled` | wp-11 | wp-14, wp-16 |
| `booking.created`, `booking.cancelled`, `booking.rebooked`, `booking.attended`, `booking.no_show` | wp-14 | wp-16 |
| `feedback.submitted` | wp-15 | wp-16 |
| `stock.low` | wp-08 | wp-16 |

Adding an event: add it to this table via an RFC note in `docs/rfcs/`.

## Ownership

| Context / area | Owner |
|---|---|
| `core/*`, ERD, conventions, CI | wp-00 |
| `Tenancy`, `Staff` | wp-01 |
| `Customers` | wp-02 |
| `Catalog` (venues, offerings, packages, discounts, tax rates) | wp-03 |
| `Payments` | wp-04 |
| `Notifications` (engine, layout, delivery, preferences) | wp-05 |
| `Players` | wp-06 |
| `Waivers` | wp-07 |
| `Inventory` | wp-08 |
| `frontend/packages/*`, app shells | wp-09 |
| `Policies` | wp-10 |
| `Scheduling` | wp-11 |
| `Credits` | wp-12 |
| `Commerce` | wp-13 |
| `Bookings` | wp-14 |
| `Feedback`, coach API | wp-15 |
| Event-driven email templates + subscribers | wp-16 |
| `Notifications.Broadcasts` | wp-17 |

If you need a change in something you don't own: write `docs/rfcs/YYYYMMDD-<slug>.md` describing it, and stub around it. Don't edit it directly.

## Definition of done (all backend WPs)

- Public context API has `@doc` and `@spec`; dialyzer clean
- Policy tests for owner / admin / coach / customer / anonymous on every action
- Tenant isolation test for every schema you own
- OpenAPI updated, TS client regenerated and compiling
- Events you publish are in the catalog and have a test asserting publication
- Seeds updated so `mix setup` produces a usable demo tenant with your data
- No `TODO` without a linked issue

## Pending decisions (build to the default unless told otherwise)

| # | Decision | Default to build |
|---|---|---|
| 1 | Stripe Connect account type & platform fee | Express accounts, direct charges on the connected account; `platform_fee_bps` per tenant, default `0`. Keep account type a config value. |
| 2 | Sales tax (GST/HST) | Tenant-configured tax rates (name + basis points). Packages, drop-ins, products have a `taxable` flag. Tax computed per line. No Stripe Tax in MVP. |
| 3 | Private-session availability model | Admins publish concrete sessions (capacity 1 for private). No coach availability rules in MVP. |
| 4 | Waitlists | Out of MVP. Don't design anything that prevents adding them. |
| 5 | Where cancellation refunds go | Policy outcomes return credits (or a % refund for pay-per-session bookings). Card refunds otherwise only via explicit admin action. |
| 6 | Custom tenant domains | Out of MVP. `tenant_domains` table exists; subdomains only. |
| 7 | Hosting region | Canadian region (player data for minors). See wp-20. |
