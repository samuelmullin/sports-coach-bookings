defmodule SportsCoachBookings.Repo.Migrations.PlayersCreatePlayers do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :players do
      # `household_id` is owned by WP-02 (Customers) and is intentionally a
      # plain uuid with no foreign key while the `households` table is unmerged.
      # See docs/rfcs/20260928-players-household-stub.md.
      add :household_id, :uuid, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :preferred_name, :string
      add :date_of_birth, :date, null: false
      add :is_self, :boolean, null: false, default: false
      add :photo_key, :string
      add :active, :boolean, null: false, default: true
      add :no_pickup_restrictions, :boolean, null: false, default: false
    end

    create index(:players, [:tenant_id, :household_id])
    create index(:players, [:tenant_id, :active])

    tenant_table :player_profiles do
      add :player_id, references(:players, type: :uuid, on_delete: :delete_all), null: false
      add :home_club, :string
      add :team, :string
      add :preferred_positions, {:array, :string}, null: false, default: []
      add :dominant_foot, :string
      add :goals, :text
      add :interests, {:array, :string}, null: false, default: []
      add :notes_from_family, :text
    end

    create unique_index(:player_profiles, [:tenant_id, :player_id])
  end
end
