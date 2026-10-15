defmodule SportsCoachBookings.Repo.Migrations.BookingsAddInvitationDeliveryTracking do
  use Ecto.Migration

  def change do
    alter table(:session_invitations) do
      add :resend_count, :integer, null: false, default: 0
      add :last_sent_at, :utc_datetime_usec
    end

    create constraint(:session_invitations, :session_invitations_resend_count_nonnegative,
             check: "resend_count >= 0"
           )
  end
end
