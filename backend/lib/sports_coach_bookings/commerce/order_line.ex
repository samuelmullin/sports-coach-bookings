defmodule SportsCoachBookings.Commerce.OrderLine do
  @moduledoc """
  A single order line. Owned by WP-13.

  Prices are snapshotted at purchase time (integer minor units). `type` is
  `package | product | drop_in`; `ref_id` is a package id, variant id, or booking
  hold id. `booking_id` links a confirmed drop-in booking for partial-refund
  idempotency, and `refunded_amount` tracks line-level refunds.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Commerce.Order

  @type t :: %__MODULE__{}

  @types [:package, :product, :drop_in]

  schema "order_lines" do
    field :tenant_id, :binary_id
    field :type, Ecto.Enum, values: @types
    field :ref_id, :binary_id
    field :booking_id, :binary_id
    field :description, :string
    field :unit_price, :integer
    field :quantity, :integer, default: 1
    field :discount_amount, :integer, default: 0
    field :tax_amount, :integer, default: 0
    field :line_total, :integer
    field :refunded_amount, :integer, default: 0
    field :refund_ref, :string
    field :taxable, :boolean, default: false

    belongs_to :order, Order, foreign_key: :order_id

    timestamps()
  end

  @doc "The line types."
  @spec types() :: [atom()]
  def types, do: @types

  @doc "The line total less any amount already refunded."
  @spec refundable_amount(t()) :: integer()
  def refundable_amount(%__MODULE__{line_total: total, refunded_amount: refunded}),
    do: total - refunded

  @doc false
  def changeset(line, attrs) do
    line
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :order_id,
      :type,
      :ref_id,
      :booking_id,
      :description,
      :unit_price,
      :quantity,
      :discount_amount,
      :tax_amount,
      :line_total,
      :refunded_amount,
      :refund_ref,
      :taxable
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :order_id, :type, :ref_id, :description])
    |> Ecto.Changeset.validate_number(:quantity, greater_than: 0)
    |> Ecto.Changeset.validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:line_total, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:refunded_amount, greater_than_or_equal_to: 0)
  end
end
