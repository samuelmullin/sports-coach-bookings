# RFC 20260928 — Customer portal session cookie

**Owner:** wp-02 (Customers). **Status:** implemented; **supersedes the wp-02
follow-up note** in `docs/rfcs/20260928-tenancy-session-cookie.md`.

## Context

The shared context requires the customer portal session to be **host-only (per
tenant)**, while the wp-01 staff session is scoped to `.sportscoachbookings.com`
(one login across tenants). The endpoint has a single `Plug.Session`, and the
wp-01 RFC explicitly left the portal cookie decision to wp-02: "use a separate
session key/plug for the portal or override the cookie domain per response".

## Decision

1. The portal session lives under a **separate session key**, `"customer_token"`,
   in the same signed cookie as the staff session (`"staff_token"`). The two keys
   never collide, so a staff session does not authenticate a customer and vice
   versa.
2. Session tokens are stored in `customer_users_tokens` (tenant-owned, RLS,
   `context = "session"`, 60-day lifetime) and are resolved **inside the
   host-resolved tenant**. Because the token row is tenant-scoped, a session
   minted on tenant A's host never resolves on tenant B's host — tenant isolation
   is enforced by RLS regardless of the cookie's domain.
3. Login/logout are handled by `SportsCoachBookingsWeb.Portal.Auth`
   (`log_in_customer/2`, `log_out_customer/1`); `Plugs.FetchCustomerUser`
   resolves the user (non-halting) and `Plugs.CustomerActor` builds the actor
   (halting) for `:require_customer` routes.
4. `:portal_session` (non-halting) is applied to the whole `/api/portal/*` scope
   so public portal endpoints still work anonymously while authenticated
   customers get a `CustomerActor`.

## Known limitation / follow-up

The endpoint's single `Plug.Session` sets one cookie `:domain`. In dev/test
`:session_domain` is `nil`, so the cookie is host-only. In production the cookie
is written with the staff domain (`.sportscoachbookings.com`), which means the
portal cookie is technically sent to sibling subdomains. This is safe today
because the customer token is tenant-scoped and RLS rejects cross-tenant
resolution, but a genuinely host-only portal cookie would require a second
session store in the endpoint (owned by wp-00). Flagged for wp-00; no security
impact given the tenant-scoped token.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited.
