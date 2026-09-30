defmodule SportsCoachBookings.Repo.Migrations.InventoryCreateStock do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :stock_levels do
      add :variant_id, references(:product_variants, type: :uuid, on_delete: :delete_all),
        null: false

      add :on_hand, :integer, null: false, default: 0
      add :reserved, :integer, null: false, default: 0
      # Cross-context (Catalog venues); plain uuid, no FK. Multi-location later.
      add :venue_id, :binary_id
      # Dedupes `stock.low` to once per variant per day.
      add :low_stock_notified_on, :date
    end

    # One row per variant per location. `venue_id` is `NULL` for the MVP's
    # single location; because Postgres treats NULLs as distinct in a unique
    # index, add an explicit partial unique for that case.
    create unique_index(:stock_levels, [:tenant_id, :variant_id, :venue_id])

    create unique_index(:stock_levels, [:tenant_id, :variant_id],
             where: "venue_id IS NULL",
             name: :stock_levels_one_per_variant_per_tenant
           )

    create constraint(:stock_levels, :stock_non_negative,
             check: "on_hand >= 0 AND reserved >= 0 AND reserved <= on_hand"
           )

    tenant_table :stock_movements do
      add :variant_id, references(:product_variants, type: :uuid, on_delete: :delete_all),
        null: false

      add :delta, :integer, null: false
      add :kind, :string, null: false
      # Cross-context (Commerce orders); plain uuid, no FK.
      add :order_id, :binary_id
      # Actor shape mirrors Core.Audit (`actor_type`/`actor_id`).
      add :actor_type, :string
      add :actor_id, :binary_id
      add :note, :text
    end

    # Append-only ledger: no `updated_at`. `tenant_table/3` adds it, so drop it.
    alter table(:stock_movements) do
      remove :updated_at, :utc_datetime_usec
    end

    create index(:stock_movements, [:tenant_id, :variant_id, :inserted_at])
    create index(:stock_movements, [:tenant_id, :order_id])

    # Idempotency: one reserved / released / sold movement per order + variant.
    create unique_index(:stock_movements, [:tenant_id, :order_id, :variant_id],
             where: "kind = 'reserved' AND order_id IS NOT NULL",
             name: :stock_movements_one_reserved_per_order_variant
           )

    create unique_index(:stock_movements, [:tenant_id, :order_id, :variant_id],
             where: "kind = 'released' AND order_id IS NOT NULL",
             name: :stock_movements_one_released_per_order_variant
           )

    create unique_index(:stock_movements, [:tenant_id, :order_id, :variant_id],
             where: "kind = 'sold' AND order_id IS NOT NULL",
             name: :stock_movements_one_sold_per_order_variant
           )

    # Append-only table: revoke mutation for the application role. The inverse is
    # supplied for rollback.
    execute(
      "REVOKE UPDATE, DELETE ON stock_movements FROM scb_app",
      "GRANT UPDATE, DELETE ON stock_movements TO scb_app"
    )
  end
end
