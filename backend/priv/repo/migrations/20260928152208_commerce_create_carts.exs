defmodule SportsCoachBookings.Repo.Migrations.CommerceCreateCarts do
  use Ecto.Migration
  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :carts do
      add :household_id, :uuid, null: false
      add :discount_code, :citext
      add :expires_at, :utc_datetime_usec
    end

    create index(:carts, [:tenant_id, :household_id])

    tenant_table :cart_lines do
      add :cart_id, references(:carts, type: :uuid, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :ref_id, :uuid, null: false
      add :quantity, :integer, null: false, default: 1
    end

    create index(:cart_lines, [:cart_id])
    create index(:cart_lines, [:tenant_id, :cart_id])

    create unique_index(:cart_lines, [:tenant_id, :cart_id, :type, :ref_id],
             name: :cart_lines_unique_ref
           )

    create constraint(:cart_lines, :cart_lines_quantity_positive, check: "quantity > 0")
  end
end
