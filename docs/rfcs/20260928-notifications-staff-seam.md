# RFC 20260928 — Staff email is a Notifications seam (wp-05 unmerged)

**Owner affected:** wp-05 (Notifications); consumer: wp-01 (Staff).
**Status:** resolved 2026-09-30.

## Context

WP-01 sends staff invitation, confirmation, and password-reset emails through
the `staff_invite` template and notification engine owned by wp-05, which is not
merged. `SportsCoachBookings.Notifications` is an empty skeleton.

## Decision

`SportsCoachBookings.Staff.Notifier` is the single seam. It calls
`Notifications.deliver(template, assigns, opts)` when that function exists, and
otherwise logs and returns `{:ok, :stubbed}`. WP-01 never calls Notifications
directly, so swapping the real engine in requires only removing the
`function_exported?/3` guard.

Templates used: `:staff_invite`, `:staff_confirm`, `:staff_reset_password`.

## Follow-up (wp-05)

Provide `Notifications.deliver/3`, register the three staff templates, and
delete the guard in `Staff.Notifier`.

## Not changed

- No wp-05 code was implemented or edited.

## Resolution (2026-09-30)

`Staff.Notifier` now calls `Notifications.deliver/3` directly; the `staff_invite`, `staff_confirm`, and `staff_reset_password` templates are registered in `config/config.exs`. The `{:ok, :stubbed}` fallback is removed.
