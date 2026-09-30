defmodule SportsCoachBookings.Commerce.Order do
  @moduledoc """
  A customer order. Owned by WP-13.

  One model for packages, pay-per-session drop-ins, and physical products. The
  money columns are integer minor units and `currency` snapshots the tenant's
  currency at order time. `number` is a per-tenant human-readable sequence
  (e.g. `A-000123`); the id is a UUIDv7.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Commerce.OrderLine

  @type t :: %__MODULE__{}

  @statuses [:pending_payment, :paid, :expired, :cancelled, :refunded, :partially_refunded]
  @payment_methods [:online, :offline]
  @refundable_statuses [:paid, :partially_refunded]

  schema "orders" do
    field :tenant_id, :binary_id
    field :number, :string
    field :household_id, :binary_id
    field :placed_by_type, :string
    field :placed_by_id, :binary_id
    field :status, Ecto.Enum, values: @statuses, default: :pending_payment
    field :currency, :string
    field :subtotal, :integer, default: 0
    field :discount_total, :integer, default: 0
    field :tax_total, :integer, default: 0
    field :total, :integer, default: 0
    field :discount_id, :binary_id
    field :payment_method, Ecto.Enum, values: @payment_methods
    field :payment_id, :binary_id
    field :refunded_total, :integer, default: 0
    field :refunded_refs, {:array, :string}, default: []
    field :expires_at, :utc_datetime_usec
    field :paid_at, :utc_datetime_usec

    has_many :lines, OrderLine, foreign_key: :order_id

    timestamps()
  end

  @doc "The order statuses."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "True when the order has been (partially) paid and can be refunded."
  @spec refundable?(t()) :: boolean()
  def refundable?(%__MODULE__{status: status}), do: status in @refundable_statuses

  @doc false
  def changeset(order, attrs) do
    order
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :number,
      :household_id,
      :placed_by_type,
      :placed_by_id,
      :status,
      :currency,
      :subtotal,
      :discount_total,
      :tax_total,
      :total,
      :discount_id,
      :payment_method,
      :payment_id,
      :refunded_total,
      :refunded_refs,
      :expires_at,
      :paid_at
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :number, :household_id, :currency])
  end
end
