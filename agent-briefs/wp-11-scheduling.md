# WP-11 — Scheduling (Sessions & Calendar)

**Phase:** 2 (critical path) · **Hard deps:** wp-03 · **Soft deps:** wp-01 (coach list), wp-14

## Goal
Admins publish concrete bookable sessions (with recurrence helpers); customers and coaches browse them on a calendar with filters and live seat availability.

## You own
`App.Scheduling`, controllers `staff/schedule/`, `portal/schedule/`. Migrations prefixed `scheduling_`.

## Schemas
- **sessions**: offering, venue, `starts_at`, `ends_at` (UTC), `capacity`, `booked_count` (**written only by wp-14** via `Scheduling.Seats`), `held_count` (same), `status` (`scheduled|cancelled|completed`), `visibility` (`public|hidden` — hidden = bookable by staff only), `title_override`, `notes_public`, `notes_staff`, `series_id` (nullable), `cancel_reason`.
- **session_coaches**: session, membership, `lead` (bool).
- **session_series**: recurrence definition used only at creation/edit time (weekday set, start time local, duration, date range, venue tz). Sessions are always materialized rows — no runtime RRULE expansion.
- Check constraints: `ends_at > starts_at`, `booked_count + held_count <= capacity`, `capacity >= 1`.

## Behaviour
- Create single session or a series (materialize all occurrences; max 200 per request). Edit one / this-and-following / whole series.
- Local-time recurrence across DST: "Tuesdays 17:00 America/Halifax" must stay 17:00 local on both sides of the DST change.
- Warn (not block) on coach double-booking and venue overlap; return conflicts in response `warnings`.
- Reducing capacity below `booked_count + held_count` → `422 capacity_below_bookings`.
- Reschedule (time/venue change) of a session with bookings → publish `session.rescheduled` (emails via wp-16).
- Cancel session → `status: cancelled`, publish `session.cancelled` (wp-14 releases/refunds bookings under `provider_cancelled` rules).
- Nightly job: mark past sessions `completed`.

## Seat API for wp-14 (`App.Scheduling.Seats`)
- `lock_session!(session_id)` → `SELECT … FOR UPDATE`, returns session.
- `adjust!(session, booked_delta, held_delta)` → updates counters (must be called inside the caller's transaction after `lock_session!`).
- Nobody else writes these columns.

## Queries
- Portal calendar: `GET /api/portal/sessions?from&to&offering_id&format&venue_id&coach_id&player_id`
  - When `player_id` (own household) is given, filter by age eligibility on the session date (`Players.age_on/2`) and flag `already_booked`.
  - Returns `seats_left`, `bookable` + `not_bookable_reason` (`full|too_late|too_early|cancelled`), using the offering's booking window.
  - Max 62-day range; index `(tenant_id, starts_at)`.
- Staff calendar: same plus hidden sessions and counts.
- Coach: `GET /api/staff/my-sessions?from&to` (sessions where the coach is assigned).

## Acceptance criteria
- DST recurrence test (Halifax, March and November transitions).
- Series edit modes tested; editing never touches sessions with bookings without an explicit confirmation flag.
- Calendar query performance: 5k sessions/tenant, response < 150 ms locally for a 31-day window.
- Isolation + policy tests. Seeds: 4 weeks of sessions across offerings.

## Out of scope
Booking logic (wp-14), coach availability rules (post-MVP), waitlists.
