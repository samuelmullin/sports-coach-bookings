defmodule SportsCoachBookings.Repo.Migrations.PlayersCreatePositionOptions do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :player_position_options do
      add :code, :string, null: false
      add :label, :string
      add :position, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true
    end

    create unique_index(:player_position_options, [:tenant_id, :code])
    create index(:player_position_options, [:tenant_id, :active])
  end
end
