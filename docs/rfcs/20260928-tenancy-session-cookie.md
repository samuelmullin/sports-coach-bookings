# RFC 20260928 — Staff session cookie scoped to the base domain

**Owner:** wp-01. **Status:** implemented; superseded for customer sessions by wp-02.

## Context

The shared context requires a single staff login across tenants
(`{slug}.sportscoachbookings.com`), while customer portal cookies are host-only
(per tenant, owned by wp-02). The endpoint has a single `Plug.Session`.

## Decision

1. The staff session cookie's `:domain` comes from
   `config :sports_coach_bookings, :session_domain`:
   - `nil` in dev/test (localhost is host-only anyway);
   - `".sportscoachbookings.com"` in `config/prod.exs`.
2. The session stores only an opaque token (`"staff_token"`); the token resolves
   to a global `StaffUser` (`SportsCoachBookingsWeb.Staff.Auth`).
3. Session tokens live in `staff_users_tokens` (`context = "session"`, 60-day
   lifetime) so they can be revoked on logout.

## Follow-up for wp-02

WP-02's customer session must be host-only. Because this endpoint has one
session store, wp-02 should either use a separate session key/plug for the
portal or override the cookie domain per response. WP-02 owns that decision and
this RFC is the note that wp-01 has claimed the shared `:session_domain` for the
staff cookie.
