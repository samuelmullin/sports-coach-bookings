# FE-02 — Customer Portal UI

**Phase:** 2 · **Hard deps:** wp-09 · **Soft deps:** wp-02, wp-03, wp-06, wp-07, wp-08, wp-10–wp-15 (mocks first)

## Goal
The branded, mobile-first site customers use to manage their household, buy packages and merch, and book sessions.

## You own
`frontend/apps/portal/src/features/**`

## Screens
### Public (no login)
- **Home:** tenant branding, featured offerings/packages, CTA to schedule.
- **Schedule:** calendar (week/agenda on mobile, week/month on desktop) filterable by offering/class type, format, venue, coach, age. If logged in, a **player selector** filters by that player's age eligibility and marks already-booked sessions. Session card: time (venue tz), venue, coach(es), seats left, price/credit cost, not-bookable reason.
- **Packages** and **Shop** (products with variant picker, stock status).
- Offering detail with policy summary.

### Account & household
- Profile, email/password change, notification preferences (marketing opt-in wording must be explicit — CASL).
- Household: members list, invite adult (email + relationship), remove (primary only), leave.
- **Players:** list; create/edit wizard — basics (name, DOB) → soccer profile (club, team, positions from tenant list, goals, interests) → emergency contacts (≥1 required) → authorized pickups → medical (optional, clearly marked private and who can see it). Show "ready to book" checklist per player (contacts, waivers).
- **Waivers:** per-player status; signing screen shows the full text, typed name + relationship + consent checkbox; sends `content_sha256` of the version displayed; download signed PDF.

### Buying & booking
- **Booking flow** from a session: choose player → pre-checks (age, waivers, contacts) with inline fix-it links → method (use credits if an eligible balance exists; otherwise pay drop-in or buy a package) → confirm (show policy summary) → success with add-to-calendar.
- **Cart & checkout:** lines, discount code, tax, total, redirect to hosted checkout, return page polling order status until paid (handle expired/cancelled).
- **Credits:** balance by scope with nearest expiry, history.
- **My bookings:** upcoming/past per player; **cancel** with outcome preview from API; **rebook** showing eligible sessions only.
- **Orders:** history, receipts, merch pickup status.
- **Feedback:** per player, shared coach feedback timeline.

## Conventions
- Mobile-first (375 px baseline); all flows completable one-handed.
- Always show times in the venue timezone; show a note if it differs from the browser timezone.
- Clear error copy for engine errors: `session_full`, `waivers_required`, `player_conflict`, `insufficient_credits`, `too_late`, etc. (map codes → i18n strings).
- Never show medical info in lists; only on the player's medical tab.

## Acceptance criteria
- Complete household journey works on mocks: register → player → waiver → package → book → cancel/rebook.
- Two different tenant brandings render correctly with no unbranded flash.
- Lighthouse mobile: performance ≥ 85, accessibility ≥ 95 on schedule and booking pages.
- Integration tests for booking flow branches (credits, pay, blocked by waiver, full).
