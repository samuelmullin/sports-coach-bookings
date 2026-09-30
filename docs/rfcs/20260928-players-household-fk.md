# RFC 20260928 — Players `household_id`: add the FK now that wp-02 is merged

**Owner:** wp-02 (proposal); change to be made by wp-06 (Players). **Status:** open.

## Context

`docs/rfcs/20260928-players-household-stub.md` (wp-06) made
`players.household_id` a plain `uuid not null` with **no** foreign key while
`households` (wp-02) was unmerged. WP-02 now creates `households` as a
tenant-owned table, so the FK can be added.

## Decision / proposal

1. In a new wp-06 migration, add
   `references(:households, type: :uuid, on_delete: :delete_all)` to
   `players.household_id` (and optionally a `belongs_to :household` association).
2. The existing `players.household_id` data is unaffected: the wp-02 seeds now
   create the `demo` household row
   (`01900000-0000-7000-8000-000000000001`) before the wp-06 players seeds run.
3. `docs/erd.md` already documents `household_id` as a cross-context reference;
   after the FK lands, wp-00 can mark the stub RFC superseded.

## Not changed

- WP-02 does **not** touch the `players` table (owned by wp-06); this RFC is the
  hand-off.
