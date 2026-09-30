# Agent Briefs — Coaching Booking SaaS

Hand each agent **two files**: `00-shared-context.md` (always) and its own brief.
Once WP-00 has merged, also point agents at `docs/erd.md` and `docs/conventions.md` in the repo.

`App` / `AppWeb` / `yourapp.com` are placeholders — replace with the real module and domain names before handing off.

## Execution order

| Phase | Briefs | Parallel? |
|---|---|---|
| 0 — Foundation | `wp-00` | No. Everything waits on this. |
| 1 — Parallel tracks | `wp-01` … `wp-10` | Yes, all ten at once. Prioritize wp-03, wp-06, wp-07, wp-10 (they feed the critical path). |
| 2 — Core flows | `wp-11` … `wp-16`, `fe-01` … `fe-03` | Partly. See dependency table. FE briefs run against mocks as soon as wp-09 lands. |
| 3 — Integration | `wp-17` … `wp-20` | wp-17 and wp-20 can start in Phase 2. wp-18/wp-19 run last. |

**Critical path:** wp-00 → wp-03 → wp-11 / wp-12 → wp-14 → wp-18. Give wp-14 to the strongest agent.

## Dependency table

| Brief | Title | Hard dependencies (must be merged) | Soft dependencies (build against contract/mocks) |
|---|---|---|---|
| wp-00 | Foundation | — | — |
| wp-01 | Tenancy, branding, staff | wp-00 | wp-05 |
| wp-02 | Customer auth & households | wp-00 | wp-05 |
| wp-03 | Catalog | wp-00 | — |
| wp-04 | Payments (Stripe) | wp-00 | — |
| wp-05 | Notifications engine | wp-00 | wp-01 (branding schema from ERD) |
| wp-06 | Players | wp-00 | wp-02, wp-14 (CoachAccess) |
| wp-07 | Waivers | wp-00 | wp-03, wp-06 |
| wp-08 | Inventory & merch | wp-00 | wp-13 |
| wp-09 | Frontend foundations | wp-00 | wp-01, wp-02 |
| wp-10 | Cancellation policies | wp-00 | wp-01 (tenant.created) |
| wp-11 | Scheduling | wp-03 | wp-14 |
| wp-12 | Credits ledger | wp-03 | wp-13 (order.paid) |
| wp-13 | Commerce / checkout | wp-03, wp-04, wp-08, wp-12 | wp-14 |
| wp-14 | Booking engine | wp-06, wp-07, wp-10, wp-11, wp-12 | wp-13 |
| wp-15 | Coach backend & feedback | wp-06, wp-11 | wp-05, wp-14 |
| wp-16 | Transactional emails | wp-05 | wp-12, wp-13, wp-14, wp-15 |
| wp-17 | Broadcasts | wp-05, wp-11 | wp-14 |
| wp-18 | End-to-end tests | everything | — |
| wp-19 | Security review | everything | — |
| wp-20 | Ops & deployment | wp-00 | — |
| fe-01 | Admin UI | wp-09 | all backend WPs (mocks) |
| fe-02 | Customer portal UI | wp-09 | all backend WPs (mocks) |
| fe-03 | Coach UI | wp-09 | wp-15 (mocks) |

## Tracking checklist

- [ ] wp-00 Foundation
- [ ] wp-01 Tenancy, branding, staff
- [ ] wp-02 Customer auth & households
- [ ] wp-03 Catalog
- [ ] wp-04 Payments
- [ ] wp-05 Notifications engine
- [ ] wp-06 Players
- [ ] wp-07 Waivers
- [ ] wp-08 Inventory
- [ ] wp-09 Frontend foundations
- [ ] wp-10 Cancellation policies
- [ ] wp-11 Scheduling
- [ ] wp-12 Credits
- [ ] wp-13 Commerce
- [ ] wp-14 Booking engine
- [ ] wp-15 Coach backend
- [ ] wp-16 Transactional emails
- [ ] wp-17 Broadcasts
- [ ] wp-18 E2E tests
- [ ] wp-19 Security review
- [ ] wp-20 Ops
- [ ] fe-01 Admin UI
- [ ] fe-02 Portal UI
- [ ] fe-03 Coach UI

## Before kickoff

Resolve (or accept the default for) each item in **Pending decisions** at the bottom of `00-shared-context.md`. Defaults are written so agents can proceed without blocking.
