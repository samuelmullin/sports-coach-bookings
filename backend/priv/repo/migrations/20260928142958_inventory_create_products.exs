defmodule SportsCoachBookings.Repo.Migrations.InventoryCreateProducts do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :products do
      add :name, :string, null: false
      add :description, :text
      add :image_keys, {:array, :string}, null: false, default: []
      add :taxable, :boolean, null: false, default: true
      add :active, :boolean, null: false, default: true
      add :visible_in_portal, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
    end

    create index(:products, [:tenant_id, :active])
    create index(:products, [:tenant_id, :visible_in_portal])
    create index(:products, [:tenant_id, :position])

    tenant_table :product_variants do
      add :product_id, references(:products, type: :uuid, on_delete: :delete_all), null: false
      add :sku, :string, null: false
      add :option_values, :map, null: false, default: %{}
      add :price, :integer, null: false
      add :low_stock_threshold, :integer
      add :active, :boolean, null: false, default: true
    end

    create unique_index(:product_variants, [:tenant_id, :sku])
    create index(:product_variants, [:tenant_id, :product_id])

    create constraint(:product_variants, :price_non_negative, check: "price >= 0")

    create constraint(:product_variants, :low_stock_threshold_non_negative,
             check: "low_stock_threshold IS NULL OR low_stock_threshold >= 0"
           )
  end
end
