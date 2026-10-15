defmodule SportsCoachBookings.Repo.Migrations.BookingsSnapshotInvitationOrganizerEmail do
  use Ecto.Migration

  def change do
    alter table(:session_invitations) do
      # Nullable for rolling compatibility with invitations created before the
      # reciprocal partner snapshot. New invitations require it in changesets.
      add :organizer_email, :citext
    end
  end
end
