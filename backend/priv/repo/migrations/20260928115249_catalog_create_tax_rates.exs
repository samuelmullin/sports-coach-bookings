defmodule SportsCoachBookings.Repo.Migrations.CatalogCreateTaxRates do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :tax_rates do
      add :name, :string, null: false
      add :rate_bps, :integer, null: false
      add :active, :boolean, null: false, default: true
    end

    create unique_index(:tax_rates, [:tenant_id],
             where: "active",
             name: :tax_rates_one_active_per_tenant
           )
  end
end
