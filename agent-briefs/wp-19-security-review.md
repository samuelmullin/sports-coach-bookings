# WP-19 — Security & Privacy Hardening

**Phase:** 3 · **Hard deps:** all backend WPs

## Goal
Systematically verify authorization and tenant isolation, harden the edges, and add the privacy features required for handling minors' data in Canada.

## You own
`test/security/**`, `AppWeb.Plugs.RateLimit`, security headers config, `App.Privacy` (export/deletion), `docs/security.md`. Fixes in other contexts go through small PRs reviewed by the owning WP (or the lead if that agent is done).

## Tasks
1. **Authorization matrix:** generate a test per route × actor (owner, admin, coach, coach-unassigned, customer-same-household, customer-other-household, customer-other-tenant, anonymous) from the router + a declarative expectations file. Fail CI on any route without an expectation.
2. **IDOR sweep:** for every route with an ID param, request another tenant's and another household's IDs → must 404/403.
3. **RLS verification:** script that lists all tables and asserts each tenant-owned table has RLS enabled + forced and a policy.
4. **Rate limiting** (Hammer or equivalent): login, register, password reset, invite accept, discount validation, checkout — per IP and per account.
5. **Headers & cookies:** CSP (script-src self; Stripe checkout is a redirect so no Stripe JS needed), HSTS, frame-ancestors none, `SameSite=Lax`, `Secure`, `HttpOnly`; CSRF on all state-changing cookie-auth routes.
6. **Uploads:** content-type sniffing, size limits, SVG sanitization, private bucket with signed GET URLs for waivers/PDFs.
7. **Webhooks:** signature verification tests with tampered payloads; replay window.
8. **Medical data:** confirm encryption at rest, audit on every read path, not present in logs (scrub params: `medical`, `password`, `token`), not in error-tracker payloads.
9. **Privacy (PIPEDA):** household data export (JSON + waiver PDFs) and account deletion/anonymization (retain orders/waivers required for legal/tax with PII minimized; document retention periods). Admin-initiated and customer-initiated flows.
10. **Static analysis:** `sobelow`, `mix hex.audit`, `mix deps.audit`, `pnpm audit` in CI.
11. **`docs/security.md`:** threat model summary, data inventory (what PII lives where), incident contacts.

## Acceptance criteria
- Matrix and IDOR suites green and enforced in CI.
- No P1/P2 findings open. Export and deletion flows tested end-to-end.
