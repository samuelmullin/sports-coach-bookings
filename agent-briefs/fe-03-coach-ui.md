# FE-03 — Coach UI

**Phase:** 2 · **Hard deps:** wp-09 · **Soft deps:** wp-15, wp-14, wp-06 (mocks first)

## Goal
A fast, phone-friendly coach experience inside `apps/admin`, shown when the membership role is `coach` (owners/admins can also access it via "My sessions" if they coach).

## You own
`frontend/apps/admin/src/features/coach/**`

## Screens
- **Today / upcoming:** list of assigned sessions grouped by day (agenda first, calendar toggle), with venue, time, booked count, quick link to directions.
- **Session roster:** player cards (name, age, positions, "medical info on file" indicator, authorized pickup summary), attendance toggles (attended / no-show) with bulk "mark all present", feedback status per player.
- **Player detail:** profile, goals, interests, emergency contacts (tap-to-call), authorized pickups, previous feedback. **Medical** behind a "View medical info" button with a notice that access is logged.
- **Feedback composer:** per player from the roster; markdown body, skill ratings (tenant tags, 1–5), "focus next session"; save internal draft or **share with family** (confirm). Edit within 48 h; option to notify family of the edit.
- **Feedback history:** everything the coach wrote, filter by player.

## Conventions
- Designed for use at the field: 375 px baseline, large tap targets, works on a slow connection (optimistic updates for attendance with retry; drafts kept in memory and restored if the request fails).
- Coach never sees admin navigation, pricing, orders, or other coaches' rosters.

## Acceptance criteria
- Full flow on mocks: open session → mark attendance → write and share feedback → see it marked shared.
- 403 from the API (player not visible) renders a friendly "not on your roster" state.
- Integration tests for attendance, feedback share, and medical reveal.
