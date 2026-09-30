defmodule SportsCoachBookings.Repo.Migrations.CatalogCreatePackages do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :packages do
      add :name, :string, null: false
      add :description, :text
      add :credit_quantity, :integer, null: false
      add :validity_days, :integer
      add :price, :integer, null: false
      add :taxable, :boolean, null: false, default: false
      add :per_household_limit, :integer
      add :active, :boolean, null: false, default: true
      add :visible_in_portal, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
    end

    create index(:packages, [:tenant_id, :active])

    tenant_table :package_offerings do
      add :package_id, references(:packages, type: :uuid, on_delete: :delete_all), null: false
      add :offering_id, references(:offerings, type: :uuid, on_delete: :delete_all), null: false
    end

    create unique_index(:package_offerings, [:package_id, :offering_id])
  end
end
