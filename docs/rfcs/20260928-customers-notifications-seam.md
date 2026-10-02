# RFC 20260928 — Customers: notifications + preferences seam

**Owner:** wp-02 (Customers). **Status:** resolved 2026-09-30.

## Context

WP-02 sends several transactional emails (account confirmation, password reset,
email change, household invitation) and exposes notification preferences. WP-05
(`SportsCoachBookings.Notifications`) owns the email engine, templates, and the
preference store and is **not merged**.

## Decision

1. `SportsCoachBookings.Customers.Notifier` is the single seam for customer
   email. It calls `Notifications.deliver/3` when that function exists (checked
   with `Code.ensure_loaded?/1` + `function_exported?/3`) and otherwise logs and
   returns `{:ok, :stubbed}`. No Swoosh mail is sent from wp-02 directly.
2. `SportsCoachBookings.Customers.Preferences.get/1` and `update/2` return
   documented defaults (`marketing_opt_in: false`, `operational: true`,
   `transactional: true`) until WP-05 lands. When WP-05 ships, set
   `config :sports_coach_bookings, :customer_preferences_module, <module>` and
   the seam delegates.
3. Customer templates use the `customer_*` / `household_invite` keys; wp-05
   registers them when it merges.

## Follow-up (when wp-05 merges)

- Implement `Notifications.deliver/3` and the preference module.
- Set `:customer_preferences_module` and delete the stub default path.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited.

## Resolution (2026-09-30)

Notifications (wp-05) is merged and wired: `Customers.Notifier` calls `Notifications.deliver/3` directly (the `{:ok, :stubbed}` fallback is removed) and `config :sports_coach_bookings, :customer_preferences_module` points at `Notifications.Preferences`.
