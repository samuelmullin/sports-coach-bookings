defmodule SportsCoachBookings.Repo.Migrations.ReservationsCreateReservationSessions do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :reservation_sessions do
      add :reservation_id, references(:reservations, type: :uuid, on_delete: :delete_all),
        null: false

      # Cross-context (Scheduling), plain uuid, no FK.
      add :session_id, :binary_id, null: false
    end

    create unique_index(:reservation_sessions, [:reservation_id, :session_id])
    create index(:reservation_sessions, [:session_id])
  end
end
