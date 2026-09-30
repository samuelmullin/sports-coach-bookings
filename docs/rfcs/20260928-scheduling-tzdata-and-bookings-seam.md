# RFC 20260928 — Scheduling: add `tzdata` and the Bookings seam

**Owner:** wp-11 (Scheduling). **Status:** implemented by wp-11.

## Context

Two cross-cutting needs surfaced while implementing wp-11:

1. **DST-safe recurrence.** The brief requires "Tuesdays 17:00 America/Halifax"
   to stay at 17:00 local across daylight-saving transitions, and all policy/event
   time math to be in UTC. Elixir's `DateTime.new/4` / `DateTime.shift_zone/3`
   need an IANA time zone database; without one they return
   `{:error, :utc_only_time_zone_database}`. The repo did not depend on one.

2. **Session rosters / `already_booked`.** Session detail and the portal calendar
   must compose a roster from Bookings (wp-14) "if present, else empty". wp-14 is
   a stub (`SportsCoachBookings.Bookings` exports no functions).

## Decision

1. Add `{:tzdata, "~> 1.2"}` to `mix.exs` and set
   `config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase` in
   `config/config.exs`. `Scheduling.Recurrence` builds each occurrence from the
   local date + local wall-clock time + venue timezone, then converts to UTC, so
   wall-clock times are DST-stable. Nothing else changes time semantics.

2. Add `SportsCoachBookings.Scheduling.Bookings`, a configurable seam defaulting
   to an empty implementation. It exposes `session_roster/1` and
   `player_booked_in_session?/2`. wp-14 (or a test) can override the source with
   `config :sports_coach_bookings, :scheduling_bookings_source, Module`.

## Impact

- New dependency and a global time zone database setting; both are additive.
- No existing table, event, or API changes. The seam returns empty answers until
  wp-14 lands, matching the brief's "else empty".
- `docs/erd.md` already documents the scheduling tables; no changes there.

## Not changed

- `docs/erd.md` is owned by wp-00; wp-11 did not edit it.
