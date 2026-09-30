defmodule SportsCoachBookings.Repo.Migrations.CreditsCreateCreditLots do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :credit_lots do
      # Cross-context (Customers); plain uuid, no FK (see docs/erd.md).
      add :household_id, :binary_id, null: false

      # Ecto enum: package_purchase | admin_grant | return_grace.
      add :source, :string, null: false

      # Cross-context (Commerce order lines); also the idempotency key for a
      # package grant (partial unique below).
      add :order_line_id, :binary_id

      # Cross-context (Catalog packages); plain uuid, no FK.
      add :package_id, :binary_id

      # Snapshot of the offerings this lot may be spent on. Empty = any offering.
      add :eligible_offering_ids, {:array, :uuid}, null: false, default: []

      add :quantity_granted, :integer, null: false
      # Cached remaining; the invariant is
      # `remaining == sum(credit_ledger_entries.delta for the lot)`.
      add :remaining, :integer, null: false
      # NULL = never expires.
      add :expires_at, :utc_datetime_usec
      add :granted_at, :utc_datetime_usec, null: false
      # Dedupes `credits.expiring_soon` to once per lot.
      add :expiring_soon_notified_at, :utc_datetime_usec
    end

    create index(:credit_lots, [:tenant_id, :household_id])

    create index(:credit_lots, [:tenant_id, :expires_at],
             where: "remaining > 0 AND expires_at IS NOT NULL",
             name: :credit_lots_expiring
           )

    # Idempotent package grants: at most one lot per order line.
    create unique_index(:credit_lots, [:tenant_id, :order_line_id],
             where: "order_line_id IS NOT NULL",
             name: :credit_lots_one_per_order_line
           )

    create constraint(:credit_lots, :credit_lots_quantity_positive, check: "quantity_granted > 0")

    create constraint(:credit_lots, :credit_lots_remaining_bounds,
             check: "remaining >= 0 AND remaining <= quantity_granted"
           )
  end
end
