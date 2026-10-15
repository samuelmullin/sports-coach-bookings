# RFC 20260928 — Players: `household_id` stub while WP-02 is unmerged

**Owner:** wp-06 (Players). **Status:** superseded by `20260928-players-household-fk.md` (resolved 2026-09-30); was a temporary stub; remove the plain-uuid
column and add the foreign key once wp-02 (`Customers.households`) merges.

## Context

`players.household_id` is a cross-context reference to the `households` table,
which is owned by wp-02 and is **not merged** in this change. `docs/erd.md`
already lists `household_id` as a uuid-only cross-context reference (the default
for new cross-context FKs), and `docs/conventions.md` §2 forbids adding a
cross-context foreign key without an RFC.

## Decision

1. Do **not** create or migrate a `households` table.
2. `players.household_id` is a plain `uuid not null` column with **no** foreign
   key and no `references/2`. A "household" is, for the purposes of Players, just
   an opaque id (`SportsCoachBookings.Core.CustomerActor.household_id`).
3. `Players.list_for_household/1` and the portal endpoints scope by this id. The
   portal controller always takes the household from the authenticated
   `CustomerActor`, never from the request body, so a customer cannot target
   another household's players.
4. Seeds use a fixed, deterministic household uuid for the `demo` tenant so
   seeding is idempotent without a `households` row.

## Follow-up (when wp-02 merges)

- Add `references(:households, type: :uuid, on_delete: :delete_all)` to
  `players.household_id` in a new migration.
- Optionally add a `belongs_to :household` association.
- At that point this RFC is superseded; wp-00 should fold the choice into
  `docs/erd.md` (it already documents the uuid-only reference).

## Not changed

- No new cross-context foreign key is introduced.
- No other context, `core/*`, or `docs/erd.md` is edited by wp-06.
