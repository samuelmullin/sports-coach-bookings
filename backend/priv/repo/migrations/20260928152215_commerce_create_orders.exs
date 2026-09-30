defmodule SportsCoachBookings.Repo.Migrations.CommerceCreateOrders do
  use Ecto.Migration
  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :orders do
      add :number, :string, null: false
      add :household_id, :uuid, null: false
      add :placed_by_type, :string
      add :placed_by_id, :uuid
      add :status, :string, null: false, default: "pending_payment"
      add :currency, :string, null: false
      add :subtotal, :integer, null: false, default: 0
      add :discount_total, :integer, null: false, default: 0
      add :tax_total, :integer, null: false, default: 0
      add :total, :integer, null: false, default: 0
      add :discount_id, :uuid
      add :payment_method, :string
      add :payment_id, :uuid
      add :refunded_total, :integer, null: false, default: 0
      add :refunded_refs, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime_usec
      add :paid_at, :utc_datetime_usec
    end

    create unique_index(:orders, [:tenant_id, :number])
    create index(:orders, [:tenant_id, :status])
    create index(:orders, [:tenant_id, :household_id])

    create constraint(:orders, :orders_amounts_non_negative,
             check: "subtotal >= 0 AND discount_total >= 0 AND tax_total >= 0 AND total >= 0"
           )

    tenant_table :order_lines do
      add :order_id, references(:orders, type: :uuid, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :ref_id, :uuid, null: false
      add :booking_id, :uuid
      add :description, :string, null: false
      add :unit_price, :integer, null: false
      add :quantity, :integer, null: false, default: 1
      add :discount_amount, :integer, null: false, default: 0
      add :tax_amount, :integer, null: false, default: 0
      add :line_total, :integer, null: false
      add :refunded_amount, :integer, null: false, default: 0
      add :refund_ref, :string
      add :taxable, :boolean, null: false, default: false
    end

    create index(:order_lines, [:order_id])
    create index(:order_lines, [:tenant_id, :order_id])

    create constraint(:order_lines, :order_lines_quantity_positive, check: "quantity > 0")

    create constraint(:order_lines, :order_lines_amounts_non_negative,
             check:
               "unit_price >= 0 AND discount_amount >= 0 AND tax_amount >= 0 AND " <>
                 "refunded_amount >= 0"
           )
  end
end
