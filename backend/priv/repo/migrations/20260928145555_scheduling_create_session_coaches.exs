defmodule SportsCoachBookings.Repo.Migrations.SchedulingCreateSessionCoaches do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :session_coaches do
      add :session_id, references(:sessions, type: :uuid, on_delete: :delete_all), null: false
      # Cross-context (Staff membership): plain uuid, no FK.
      add :membership_id, :binary_id, null: false
      add :lead, :boolean, null: false, default: false
    end

    create unique_index(:session_coaches, [:session_id, :membership_id])
    create index(:session_coaches, [:tenant_id, :membership_id])
  end
end
