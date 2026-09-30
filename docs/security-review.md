# SportsCoachBookings — Security Review (WP-19)

Owner: wp-19. Status: complete. This document records the methodology, the
findings and fixes, the accepted risks (with rationale), and the exact evidence
for the security gates. It complements `docs/conventions.md` (architecture
rules) and `docs/ops.md` (operations).

> The wp-19 brief also names `docs/security.md` for the threat model / data
> inventory / incident contacts; those sections live here (§7–§9) so there is a
> single source of truth.

---

## 1. Scope and method

A hands-on review of the running backend, not a checklist. For each area we
read the code, attempted the abuse, fixed what was broken, and added a
regression test.

| Area | Method |
|---|---|
| Authorization | Every controller action traced to its context `.Policy`; added an actor-matrix controller test |
| Tenancy / RLS | Catalogued every table with a `tenant_id`; asserted `ENABLE`/`FORCE` RLS + a policy via `pg_class`/`pg_policies`; reviewed every `skip_tenant: true` |
| Auth / session | Reviewed password hashing, token lifetime + single-use, confirmation/reset, cookie flags, session fixation, enumeration, invite brute-force |
| Rate limiting | Implemented the wp-01/wp-02 hook (`Plugs.RateLimit`) with an ETS limiter and wired it to the unauthenticated/sensitive routes |
| Webhooks | Reviewed Stripe + Svix signature verification over the raw body, the replay window, and idempotency; tests already cover tampered payloads and replays |
| Input validation | Upload type/size/sniffing, SVG sanitisation, mass-assignment, raw SQL, SSRF, open redirect |
| Secrets / headers | Searched for secrets in code/config; added security headers, cookie flags, log filtering |
| Static / dynamic analysis | `sobelow`, `dialyzer`, `credo`, `format`, `deps.unlock`, `hex.audit` |

The tenant is only ever resolved from the request host by
`SportsCoachBookingsWeb.Plugs.ResolveTenant`; no endpoint accepts a tenant id
from a body, query or header (verified by reading every controller and the
router).

---

## 2. Findings

Severity uses P1 (critical) … P4 (informational). All P1/P2 findings are fixed.

| # | Sev | Area | Finding | Fix |
|---|---|---|---|---|
| 1 | **P1** | Rate limiting | `Plugs.RateLimit` was a no-op, so login, signup, password reset, invite acceptance and webhooks were unthrottled (credential stuffing, email bombing, invite-token brute force) | Implemented `SportsCoachBookings.RateLimiter` (ETS fixed window) and wired the plug into the auth, signup, invite, checkout, discount and webhook pipelines |
| 2 | **P2** | Dependencies | `mint 1.10.1` had 1 HIGH + 2 MEDIUM advisories (HPACK cookie memory exhaustion, oversized-frame buffering, response smuggling) | `mix deps.update mint` → `1.11.0`; `mix hex.audit` clean |
| 3 | **P2** | Headers | No `Content-Security-Policy`, `X-Frame-Options` or `X-Content-Type-Options` on responses (clickjacking, MIME sniffing) | Added `SportsCoachBookingsWeb.Plugs.SecurityHeaders` at the endpoint (CSP `default-src 'self'`, `frame-ancestors 'none'`, `X-Frame-Options: DENY`, nosniff, referrer-policy, permissions-policy). HSTS is set by `force_ssl` in prod |
| 4 | **P2** | Auth/session | Session cookies did not set `Secure` (only the prod `force_ssl` redirect) and did not renew the session id on login (fixation) | Cookie options now set `http_only: true`, `secure: true` in prod, `SameSite=Lax`; `Staff.Auth`/`Portal.Auth` call `configure_session(renew: true)` on login |
| 5 | **P2** | Open redirect | `POST /api/staff/payments/connect/onboarding` passed a client-supplied `return_url`/`refresh_url` to Stripe | New `SportsCoachBookingsWeb.SafeRedirect` only allows same-site `https` (or localhost `http`); otherwise falls back to the configured default |
| 6 | **P2** | DoS | `String.to_atom/1` on untrusted input (`Notifications` assign keys, Stripe `normalize_type/1`) — unbounded atom-table growth | `String.to_existing_atom/1` with a string fallback; unknown provider types map to `:unknown` |
| 7 | **P2** | Uploads | Uploads trusted the client `content_type`; SVG rejection list was thin | Magic-byte sniffing for PNG/JPEG/WebP/SVG when bytes transit the app; extended SVG rejection (`<animate>`, `<!DOCTYPE>`, `<!ENTITY>`, external `href`/`url()`, `<use>`) |
| 8 | P3 | Tenancy | `audit_events` RLS policy used `current_setting('app.tenant_id', true)::uuid` while every other table uses `NULLIF(current_setting(...), '')::uuid` (an empty GUC raises rather than returning no rows) | Migration `20260928210000_core_audit_events_policy_nullif` recreates the policy with the `NULLIF` predicate |
| 9 | P3 | Traversal | SPA static serving used a string-prefix check (`/root` accepted `/root-evil`) | Boundary-aware `within_root?/2` (`candidate == root or starts_with?(candidate, root <> "/")`) |
| 10 | P3 | Dialyzer | `mix dialyzer` emitted 81 warnings (dead branches, unknown types, `Ecto.Multi` opacity) | Fixed the real ones (added the missing `Policy.actor/0` type, a real `balance_string/1` bug, redundant clauses) and suppressed 47 justified `Ecto.Multi` false positives |
| 11 | P3 | Logging | No `:filter_parameters`, so `password`/`token`/`medical` could appear in logs/telemetry | Added `config :phoenix, :filter_parameters` and `config :logger, :filter_parameters` |
| 12 | P4 | Enumeration | Registration returns a changeset validation error for a duplicate email | Accepted (see §4); rate-limited and only reveals existence on the tenant/staff registration path |

### Authorization / IDOR

Every controller action was traced to its owning context policy
(`SportsCoachBookings.<Context>.Policy`), which is called **before** the context
function. The actor plugs (`StaffActor`, `CustomerActor`) build the actor from
the session and the host-resolved tenant/membership; a client cannot supply an
actor. Owner-only actions (`transfer_ownership`, `delete`) are policy-gated by
role.

`test/security/authorization_matrix_test.exs` asserts the controller boundary
for anonymous / customer / coach / admin / owner, and
`test/security/idor_test.exs` requests another tenant's and another household's
ids across staff and portal routes and requires `404`/`403`.

### Tenancy / RLS

`test/security/rls_verification_test.exs` enumerates every table with a
`tenant_id` column and asserts `relrowsecurity` **and** `relforcerowsecurity`
are true and that a policy exists; it also asserts the application role is not a
superuser and has no `BYPASSRLS`. `skip_tenant: true` appears only in
platform-level queries (host resolution, provider webhook storage/processing,
tenant picker self-read) and is documented at each site.

---

## 3. Rate limiting approach

**Choice: an in-app ETS fixed-window limiter, no new dependency.**

- `SportsCoachBookings.RateLimiter` — a supervised process owns one public ETS
  table; `hit(keys, limit, window)` increments each key and denies when any key
  is over its limit. Stale windows are pruned every minute.
- `SportsCoachBookingsWeb.Plugs.RateLimit` — reads the config, builds keys and
  halts `429` with the standard error envelope (`too_many_requests`) and a
  `Retry-After` header.

Keys are `scope|ip:<client>` plus `scope|tenant:<id>` (only when a tenant is
resolved) plus `scope|acct:<email>` when the route supplies `:account_param`.
The client IP prefers the Fly `fly-client-ip` edge header (authoritative and
spoof-stripped), falls back to `x-forwarded-for`, then the socket peer.

Wired routes:

| Pipeline | Routes | Limit |
|---|---|---|
| `:rate_limit_auth` | platform login/logout/registration/confirmation/password reset; portal registration/login/logout/confirmation/password reset/invite accept | 30 / 60s per IP + email + tenant |
| `:rate_limit_signup` | tenant signup, slug availability | 10 / 3600s per IP + email |
| `:rate_limit_invite` | staff invite show/accept | 30 / 60s per IP + tenant |
| `:rate_limit_checkout` | portal checkout | 30 / 60s |
| `:rate_limit_discount` | staff catalog (discount validation/reorder/writes) | 120 / 60s |
| `:rate_limit_webhook` | Stripe + Resend webhooks | 300 / 60s per IP |

`test/security/rate_limit_test.exs` covers the limiter and an end-to-end `429`.
Enforcement is disabled in `config/test.exs` because the ETS table is shared
across async tests; the dedicated test enables it explicitly.

**Why not Hammer/Redis:** the app is a single-region deploy with stateless web
nodes (`docs/ops.md` §9); per-node fixed windows are enough. See §4 for the
limitation.

---

## 4. Accepted risks

| Risk | Rationale |
|---|---|
| Rate limits are **per node**, not shared | Stateless single-region deploy; a multi-node fleet multiplies effective limits. Revisit with a Redis/Hammer backend if the fleet grows or limits need to be exact. |
| **CSRF**: no `protect_from_forgery` token | The API is JSON-only and cookie-authenticated. Cookies are `SameSite=Lax`, so browsers do not attach them to cross-site `POST/PUT/PATCH/DELETE`; `Plugs.VerifyOrigin` additionally rejects state-changing requests whose `Origin` is not the request host. There is no `GET`-based state change. A CSRF token scheme would require an SPA token bootstrap and is a deliberate follow-up. |
| **Email enumeration** on registration | A duplicate email returns a `422` validation error. The endpoint is rate-limited (per IP + email). Confirmation-resend and password-reset are already generic. Low impact: it reveals account existence only, not credentials or data. |
| Platform tables with a `tenant_id` but **no RLS**: `tenant_domains`, `notifications_delivery_refs` | Required to resolve a tenant/its domains (host) and a provider message id (inbound webhook) **before** a tenant exists in context. `tenant_domains` is listed as a platform table in `docs/conventions.md` §1; `notifications_delivery_refs` stores only `provider`, `provider_ref`, `tenant_id`, `delivery_id` and is queried only by the globally-unique `(provider, provider_ref)`. Both are asserted as explicit allow-listed exceptions by the RLS test. |
| S3 uploads cannot be content-sniffed by the app | Presigned PUTs send bytes straight to S3; the app only sees the declared `Content-Type`. The bucket must enforce the content type and block executables; the signed header and private bucket policy are the control (the local Fake store sniffs bytes). |
| Sobelow `XSS.SendResp` / `Traversal` / `RCE` skips | `email_preview_controller` is dev-only; the unsubscribe page interpolates constants only; SPA `send_file` is boundary-checked; notification EEx templates and release seeds are developer-authored, never user input. Each has an inline `# sobelow_skip` with the reason. |
| Dialyzer `.dialyzer_ignore.exs` | Only `:call_without_opaque` for the Ecto `Multi` helpers in 7 context files — a known Dialyxir false positive caused by `Ecto.Multi.t/0` opacity. Runtime is exercised by the suite. Removing the helpers is a Core change (`docs/rfcs/20260928-core-tenant-tx-multi.md`). |

---

## 5. Evidence — commands and results

Run from `backend/` (`export PATH="$HOME/.asdf/shims:$PATH"`).

| Gate | Command | Result |
|---|---|---|
| Tests | `mix test` | `Result: 752 passed (5 properties, 747 tests)` |
| Format | `mix format --check-formatted` | exit 0 (clean) |
| Credo | `mix credo --strict` | `found no issues` (528 files, 4357 mods/funs) |
| Sobelow | `mix sobelow --config` | `... SCAN COMPLETE ...`, exit 0; accepted findings carry `# sobelow_skip` and are in §4 |
| Dialyzer | `mix dialyzer` | `Total errors: 47, Skipped: 47, Unnecessary Skips: 0` → `done (passed successfully)`, exit 0 |
| Precommit | `mix precommit` | compile `--warnings-as-errors` + `deps.unlock --unused` + format + credo + test all green |
| Unused deps | `mix deps.unlock --check-unused` | exit 0 |
| Hex advisories | `mix hex.audit` | `No retired or security advisory packages found` |
| OpenAPI drift | `mix app.openapi.export` | no drift (no endpoints changed) |

`mix deps.audit` is not available in this project (the `mix_audit` dependency is
not installed); `mix hex.audit` is the equivalent check and is clean.

The `# sobelow_skip` markers are honoured because `.sobelow-conf` sets
`skip: true` and `exit: "low"`.

---

## 6. Tests added

`test/security/` (new):

- `rls_verification_test.exs` — RLS enabled/forced/policy for every
  `tenant_id` table; app role is not superuser/BYPASSRLS; platform allow-list.
- `authorization_matrix_test.exs` — anonymous/customer/coach/admin/owner across
  representative routes.
- `idor_test.exs` — cross-tenant and cross-household ID access returns `403`/`404`.
- `rate_limit_test.exs` — limiter unit tests + end-to-end `429` with
  `Retry-After`.
- `security_headers_test.exs` — headers on API and error responses.
- `open_redirect_test.exs` — `SafeRedirect` accepts same-site, rejects off-site.
- `upload_validation_test.exs` — allow-list, size cap, magic-byte sniffing, SVG
  rejection.

---

## 7. Threat model (summary)

- **Trust boundaries.** Internet → Phoenix endpoint; tenant boundary = host
  (`ResolveTenant` + RLS); staff identity is global, customer identity is
  per-tenant; provider webhooks are unauthenticated but signature-verified.
- **Primary assets.** Minors' PII and medical data, payment/Stripe Connect
  credentials, tenant configuration, credits/ledger integrity.
- **Adversaries considered.** Unauthenticated internet (credential stuffing,
  enumeration, DoS, webhook forgery, upload/redirect abuse); a malicious or
  curious authenticated user (IDOR, privilege escalation, cross-tenant access);
  a compromised tenant subdomain.
- **Controls.** Deny-by-default policies at every controller; Postgres RLS
  enabled+forced with a non-superuser app role; field-level encryption (Cloak)
  for medical data with reads audited; append-only ledgers; idempotent webhooks
  and events; rate limiting; security headers; content-sniffed uploads; private
  buckets with signed URLs; secrets only via env.

## 8. Data inventory (PII)

| Data | Location | Protection |
|---|---|---|
| Staff identity (email, password hash) | `staff_users` (platform) | PBKDF2-HMAC-SHA256, 120k iterations; password `redact: true` |
| Customer identity (email, phone, name) | `customer_users` (tenant-owned) | RLS; password hash as above; hashed email-change tokens |
| Households & members | `households`, `household_members` | RLS; host-only portal session |
| Player profiles / guardians / emergency contacts / authorized pickups | `players`, `players_emergency_contacts`, `authorized_pickups` | RLS |
| **Medical data (minors)** | `medical_info` | RLS + Cloak AES-256-GCM field encryption; every read audited; scrubbed from logs |
| Waiver signatures | `waiver_signatures` | RLS; IP/user-agent captured; PDF in private storage |
| Orders, payments, refunds | `orders`, `payments`, `refunds` | RLS; integer minor units; provider refs only |
| Credit ledger | `credit_ledger_entries`, `credit_lots` | RLS; append-only |
| Email deliveries / webhook events | `deliveries`, `messages`, provider tables | retried idempotently; suppression list |
| Audit trail | `audit_events` | RLS; append-only |

## 9. Incident contacts

- **Security lead / on-call:** `<<PLACEHOLDER: name + channel>>` (fill in before
  first production deploy).
- **Data-protection / privacy officer (PIPEDA):** `<<PLACEHOLDER>>`.
- **Stripe:** report compromise via the Stripe Dashboard; rotate
  `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` (`docs/ops.md` §8).
- **Resend/Svix:** rotate `RESEND_API_KEY` and `RESEND_WEBHOOK_SECRET`.
- **Fly/Postgres/S3:** rotate `SECRET_KEY_BASE`, `DATABASE_URL` credentials,
  `S3_*` and `PLAYER_MEDICAL_ENCRYPTION_KEY` (Cloak rotation runbook in
  `docs/ops.md` §8).

---

## 10. Not implemented / residual work

- **PIPEDA household export / deletion** (`App.Privacy`) from the wp-19 brief is
  **not implemented** in this change: it was outside the explicit scope of the
  execution brief (authorization, tenancy, auth/session, rate limiting,
  webhooks, input validation, secrets/headers, dependencies, static analysis).
  It remains an open item; the data inventory in §8 is the input it needs.
- Rate limits are per node (see §4).
- `mix dialyzer` suppression list should shrink as Core removes the
  `Ecto.Multi` helper workaround.
