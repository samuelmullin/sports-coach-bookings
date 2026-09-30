# WP-06 — Players, Profiles, Contacts, Medical

**Phase:** 1 (feeds critical path) · **Hard deps:** wp-00 · **Soft deps:** wp-02 (household), wp-14 (`CoachAccess` stub)

## Goal
Households manage the players they book for — including minors — with sports profile, emergency contacts, authorized pickups, and encrypted medical details.

## You own
`App.Players`, controllers `portal/players/`, `staff/players/`. Migrations prefixed `players_`.

## Schemas
- **players**: household, first/last name, preferred name, `date_of_birth`, `is_self` (adult booking for themselves), photo_key (optional), `active`.
- **player_profiles**: `home_club`, `team`, `preferred_positions` (array of strings), `dominant_foot`/handedness (optional), `goals` (text), `interests` (array/tags), `notes_from_family` (text).
- **tenant position options**: `player_position_options` (tenant-configurable list, seeded with soccer positions: GK, CB, FB, DM, CM, AM, W, ST). Validation: positions must come from the list.
- **emergency_contacts**: name, relationship, phone, alt phone, `priority` (1..n). At least one required before the player can be booked (expose `Players.bookable?/1` reasons).
- **authorized_pickups**: name, relationship, phone, notes. Optional list; an explicit `no_pickup_restrictions` flag is allowed (e.g. adults, teens who leave alone).
- **medical_info** (encrypted with `cloak_ecto`): `allergies`, `conditions`, `medications`, `notes`, `has_medical_info` (unencrypted boolean for quick display). One row per player.

## Access rules (enforce in `Players.Policy`)
| Actor | Profile / contacts / pickups | Medical |
|---|---|---|
| Household manager | Full CRUD for own household's players | Full CRUD |
| Owner / admin | Read + update | Read (audited) + update (audited) |
| Coach | Read **only if** `CoachAccess.player_visible?(actor, player_id)` | Read only if visible (audited on every read) |
| Other customers | None | None |

Every medical read writes `Audit.record(actor, "player.medical.read", player, %{})`. Serve medical info from a **separate endpoint** (`GET …/players/:id/medical`) so it's never included in list payloads.

## Public API
- `Players.get_player!/1`, `list_for_household/1`, `age_on(player, date) :: integer`, `bookable?(player) :: :ok | {:error, [reason]}`
- `Players.summary_for_roster(player_ids)` (name, age, positions, `has_medical_info`, emergency contact primary) — used by wp-15.
- `Players.search(term)` for staff search (used by wp-02 admin search).
- Events: `player.created`, `player.updated`.

## Acceptance criteria
- Coach with no bookings for a player gets 403; tests use a stubbed `CoachAccess` returning true/false.
- Medical fields are ciphertext in the DB (test with raw SQL).
- Audit rows created for each medical read by staff.
- `age_on` correct across leap-day birthdays.
- Isolation + policy tests.

## Out of scope
Waivers (wp-07), UI (fe-02), player photos beyond storing a key.
