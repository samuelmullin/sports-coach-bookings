# RFC 20260928 — Customers: rate-limiting hook point

**Owner:** wp-02 (Customers); enforcement owned by wp-19. **Status:** implemented by wp-19 (`Plugs.RateLimit` + `RateLimiter`). Limits are per node; see `docs/security-review.md` §4.

## Context

The customer auth endpoints (registration, login, confirmation resend, password
reset) are unauthenticated and are prime targets for credential stuffing,
enumeration, and email-bombing. Rate limiting is owned by wp-19 and is not
merged; the wp-02 brief asks only for a hook point.

## Decision

`SportsCoachBookingsWeb.Plugs.RateLimit` is a no-op plug
(`call/2` returns the conn unchanged). It is available to add to the customer
auth pipelines (`:portal_session`) when wp-19 lands, without restructuring the
router. wp-19 owns the implementation (bucket keys, storage, response shape —
`429` with code `too_many_requests` already exists in `ErrorJSON`).

## Follow-up (when wp-19 merges)

- Implement `RateLimit` (e.g. Hammer/Ecto-backed) and add it to the portal auth
  routes, keyed by IP + email + tenant.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited.
