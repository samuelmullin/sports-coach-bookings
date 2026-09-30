# FE-01 — Admin UI (Owners & Admins)

**Phase:** 2 · **Hard deps:** wp-09 · **Soft deps:** all backend WPs (build against MSW mocks, switch to live API as each merges)

## Goal
Every owner/admin screen in `apps/admin`. This brief is large — it can be split across agents by section (A–E), since sections share only the shell from wp-09.

## You own
`frontend/apps/admin/src/features/{dashboard,settings,branding,team,payments,catalog,schedule,bookings,customers,orders,inventory,waivers,policies,messaging}/**`

## A — Setup & settings
- **Onboarding checklist** on the dashboard: branding, payments connected, venue, offering, package, sessions, waiver, policy. Each links to its screen; state derived from API.
- **Settings:** tenant details, timezone, currency (disabled when locked), tax rate, reminder timing.
- **Branding editor:** logo/favicon upload, color pickers with live preview of a portal card + button + email header, contrast warnings.
- **Team:** list, invite (email + role), change role, remove; owner-only transfer ownership.
- **Payments:** Stripe connect status, start/resume onboarding, requirements due.

## B — Catalog & policies
- Venues, offerings (age range, format, duration, capacity, credit cost, drop-in price, booking window), packages (credits, eligible offerings multi-select, validity, price, limits), discounts (code/automatic, rules, usage stats).
- Cancellation policies: tier editor (sortable rows), no-show, rebook rules, customer-facing summary, **simulator** ("cancel X hours before → outcome"), offering assignments.
- Waivers: template list, markdown editor with preview, publish new version (confirm dialog explains re-sign impact), signatures list, PDF download.

## C — Schedule & bookings
- **Calendar** (week/month/agenda) with filters (venue, offering, coach), color by offering, seats badge.
- Create session / series (recurrence form with DST-safe local times), conflict warnings display, edit single/following/series, cancel session (reason, impact count), reschedule.
- **Session detail:** roster, attendance, book on behalf (search household → pick player → method credits/comp/paid), cancel booking with outcome preview + override.

## D — Customers & orders
- Customer/household search; household detail tabs: members, players (profile, contacts, pickups, medical behind a "reveal" action that shows an audit notice), waivers status, bookings, credits (balance, ledger, adjust/grant), orders, emails (delivery log, resend).
- Orders list + detail, refund dialog (line selection, credits-used warning), offline order creation.

## E — Inventory & messaging
- Products/variants CRUD with image upload, stock receive/adjust, movement history, fulfillment queue (ready / picked up).
- Broadcasts: composer (markdown + preview), segment builder with live recipient count, category explanation (operational vs marketing), schedule, send test, history with stats.

## Conventions
- Forms: `react-hook-form` + `zod`, server `fields` errors mapped inline.
- All times displayed in the venue timezone with the tz abbreviation.
- Destructive actions use `ConfirmDialog` with a description of consequences returned by the API where available.
- Empty states link to the relevant setup step.

## Acceptance criteria
- Every screen works on mocks and against the live API once its backend WP is merged.
- Component/integration tests (Vitest + Testing Library + MSW) for each form's happy path and a server-error path.
- Usable at 1280 px and tablet (1024 px); dashboard, calendar, and session detail usable on mobile.
