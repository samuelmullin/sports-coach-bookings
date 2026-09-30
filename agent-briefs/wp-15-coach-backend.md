# WP-15 — Coach API & Player Feedback

**Phase:** 2 · **Hard deps:** wp-06, wp-11 · **Soft deps:** wp-05, wp-14 (`CoachAccess`, attendance)

## Goal
Coaches see their sessions and rosters, view details of their players, mark attendance, and write feedback that is emailed to the household.

## You own
`App.Feedback`, controllers `staff/coach/` and `staff/feedback/`. Migrations prefixed `feedback_`.

## Schemas
- **session_feedback**: session, player, coach membership, `body` (markdown, ≤ 5k chars), `skill_ratings` (map of tag → 1..5, optional), `focus_next` (text), `visibility` (`internal|shared`), `shared_at`, `edited_at`.
- **feedback_skill_tags**: tenant-configurable list (seed: first touch, passing, shooting, 1v1 defending, positioning, work rate, communication).
- One feedback per `(session, player, coach)`; editable by its author for 48 h after sharing (edits are versioned in `booking_events`-style history or a `feedback_revisions` table).

## Endpoints (coach role; owner/admin can use them too)
- `GET /api/staff/coach/sessions?from&to` — assigned sessions with counts (delegates to `Scheduling`).
- `GET /api/staff/coach/sessions/:id/roster` — bookings + `Players.summary_for_roster/1` + attendance + feedback status per player.
- `GET /api/staff/coach/players/:id` — profile, positions, goals, emergency contacts, authorized pickups, recent feedback from this tenant's coaches; medical via the wp-06 endpoint (audited). 403 unless `CoachAccess.player_visible?`.
- `POST /api/staff/coach/sessions/:id/attendance` — bulk mark (delegates to `Bookings`).
- Feedback: create (draft/internal), share (sets `visibility: shared`, publishes `feedback.submitted`), edit, list per player.
- Admin: list all feedback (filters: coach, player, date), read any.

## Portal
- `GET /api/portal/players/:id/feedback` — shared feedback only, newest first.

## Acceptance criteria
- Coach cannot see rosters of sessions they aren't assigned to, nor players outside `CoachAccess`.
- Sharing publishes exactly one `feedback.submitted`; editing after sharing doesn't re-send (wp-16 may send an "updated" email only if the edit flag `notify: true` is passed).
- Internal feedback never appears in portal responses.
- Isolation + policy tests.

## Out of scope
Email content (wp-16), video/attachments in feedback, UI (fe-03).
