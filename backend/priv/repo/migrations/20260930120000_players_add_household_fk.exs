defmodule SportsCoachBookings.Repo.Migrations.PlayersAddHouseholdFk do
  use Ecto.Migration

  # Adds `players.household_id -> households.id`
  # (docs/rfcs/20260928-players-household-fk.md).
  #
  # Rolled out in two steps so a bad dataset fails with a readable message
  # instead of a bare constraint error, and so the write lock is short:
  #   1. ADD CONSTRAINT ... NOT VALID (enforced for new writes immediately)
  #   2. fail loudly if any orphaned players exist, then VALIDATE CONSTRAINT
  #
  # `ON DELETE RESTRICT` (the RFC proposed CASCADE): bookings, credits, and
  # waivers reference players without FKs, so a cascading household delete would
  # silently orphan them. Household deletion must remove players explicitly.
  def up do
    execute """
    ALTER TABLE players
      ADD CONSTRAINT players_household_id_fkey
      FOREIGN KEY (household_id) REFERENCES households (id)
      ON DELETE RESTRICT NOT VALID
    """

    # Migrations run as the table owner, so RLS does not hide rows here.
    execute """
    DO $$
    DECLARE orphans integer;
    BEGIN
      SELECT count(*) INTO orphans
        FROM players p
        LEFT JOIN households h ON h.id = p.household_id
       WHERE h.id IS NULL;

      IF orphans > 0 THEN
        RAISE EXCEPTION
          'players_household_id_fkey: % player row(s) reference a missing household; repair or remove them (see docs/rfcs/20260928-players-household-fk.md) and re-run',
          orphans;
      END IF;
    END
    $$
    """

    execute "ALTER TABLE players VALIDATE CONSTRAINT players_household_id_fkey"
  end

  def down do
    execute "ALTER TABLE players DROP CONSTRAINT players_household_id_fkey"
  end
end
