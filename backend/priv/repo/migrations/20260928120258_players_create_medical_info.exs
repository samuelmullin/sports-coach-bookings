defmodule SportsCoachBookings.Repo.Migrations.PlayersCreateMedicalInfo do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :medical_info do
      add :player_id, references(:players, type: :uuid, on_delete: :delete_all), null: false
      # Encrypted at rest with cloak_ecto (AES-GCM). Stored as `bytea`.
      add :allergies, :binary
      add :conditions, :binary
      add :medications, :binary
      add :notes, :binary
      add :has_medical_info, :boolean, null: false, default: false
    end

    create unique_index(:medical_info, [:tenant_id, :player_id])
  end
end
