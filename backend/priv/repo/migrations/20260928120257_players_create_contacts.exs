defmodule SportsCoachBookings.Repo.Migrations.PlayersCreateContacts do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :emergency_contacts do
      add :player_id, references(:players, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :relationship, :string
      add :phone, :string, null: false
      add :alt_phone, :string
      add :priority, :integer, null: false
    end

    create index(:emergency_contacts, [:tenant_id, :player_id])

    tenant_table :authorized_pickups do
      add :player_id, references(:players, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :relationship, :string
      add :phone, :string
      add :notes, :text
    end

    create index(:authorized_pickups, [:tenant_id, :player_id])
  end
end
