defmodule SportsCoachBookings.Repo.Migrations.PaymentsCreatePayments do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # One row per hosted-checkout attempt. Tenant-owned (RLS enabled and forced).
    # `order_id` is a cross-context reference to Commerce (uuid only, no FK).
    tenant_table :payments do
      add :provider, :string, null: false
      add :order_id, :uuid
      add :checkout_ref, :string
      add :payment_ref, :string
      add :amount, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :raw, :map, null: false, default: %{}
    end

    create index(:payments, [:order_id])
    create index(:payments, [:tenant_id, :checkout_ref])

    # `unique(provider, payment_ref)` dedupes payment intents; NULLs (pending
    # rows) never collide. This is the reconciliation key for webhooks.
    create unique_index(:payments, [:provider, :payment_ref])
  end
end
