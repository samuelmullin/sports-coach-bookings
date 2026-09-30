defmodule SportsCoachBookings.Repo.Migrations.InventoryCreateFulfillments do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :fulfillments do
      # Cross-context (Commerce order lines); plain uuid, no FK.
      add :order_line_id, :binary_id, null: false
      # Same-context variant, kept so the portal can render the item without a
      # cross-context lookup. Nilable so variant cleanup never destroys history.
      add :variant_id, references(:product_variants, type: :uuid, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending"
      # Cross-context (Catalog venues).
      add :pickup_venue_id, :binary_id
      add :picked_up_at, :utc_datetime_usec
      # Cross-context (Staff membership that handed the item over).
      add :picked_up_by, :binary_id
    end

    # One fulfillment per order line makes event replay idempotent.
    create unique_index(:fulfillments, [:tenant_id, :order_line_id])
    create index(:fulfillments, [:tenant_id, :status])
    create index(:fulfillments, [:tenant_id, :variant_id])
  end
end
