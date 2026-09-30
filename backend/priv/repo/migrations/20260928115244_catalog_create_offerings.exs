defmodule SportsCoachBookings.Repo.Migrations.CatalogCreateOfferings do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :offerings do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :format, :string, null: false
      add :min_age, :integer
      add :max_age, :integer
      add :duration_minutes, :integer, null: false
      add :default_capacity, :integer, null: false, default: 1
      add :credit_cost, :integer, null: false, default: 1
      add :drop_in_price, :integer
      add :taxable, :boolean, null: false, default: false
      add :bookable_until_minutes_before, :integer, null: false, default: 60
      add :bookable_from_days_ahead, :integer
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      add :image_key, :string
    end

    create unique_index(:offerings, [:tenant_id, :slug])
    create index(:offerings, [:tenant_id, :active, :format])
  end
end
