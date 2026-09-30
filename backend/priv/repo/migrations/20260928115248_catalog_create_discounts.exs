defmodule SportsCoachBookings.Repo.Migrations.CatalogCreateDiscounts do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :discounts do
      add :code, :citext
      add :kind, :string, null: false
      add :value, :integer, null: false
      add :applies_to, :string, null: false, default: "all"
      add :starts_at, :utc_datetime_usec
      add :ends_at, :utc_datetime_usec
      add :max_redemptions, :integer
      add :per_household_limit, :integer
      add :min_subtotal, :integer
      add :active, :boolean, null: false, default: true
    end

    create index(:discounts, [:tenant_id, :active])
    create unique_index(:discounts, [:tenant_id, :code], where: "code IS NOT NULL")

    tenant_table :discount_targets do
      add :discount_id, references(:discounts, type: :uuid, on_delete: :delete_all), null: false
      add :target_type, :string, null: false
      add :target_id, :uuid, null: false
    end

    create index(:discount_targets, [:discount_id])
    create index(:discount_targets, [:target_type, :target_id])

    tenant_table :discount_redemptions do
      add :discount_id, references(:discounts, type: :uuid, on_delete: :delete_all), null: false
      add :household_id, :uuid, null: false
      add :order_id, :uuid, null: false
    end

    create unique_index(:discount_redemptions, [:tenant_id, :discount_id, :order_id])
    create index(:discount_redemptions, [:tenant_id, :discount_id])
    create index(:discount_redemptions, [:tenant_id, :household_id])
  end
end
