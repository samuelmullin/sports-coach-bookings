defmodule SportsCoachBookings.Inventory.Fulfillment do
  @moduledoc """
  A pickup obligation for one order line. Owned by WP-08.

  Customers pick physical items up at a venue, so a fulfillment tracks the
  order line through `pending -> ready_for_pickup -> picked_up` (or
  `cancelled`). `(tenant_id, order_line_id)` is unique so replaying
  `order.paid` cannot create a duplicate.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Inventory.ProductVariant

  @type t :: %__MODULE__{}

  @statuses [:pending, :ready_for_pickup, :picked_up, :cancelled]

  schema "fulfillments" do
    field :tenant_id, :binary_id
    field :order_line_id, :binary_id
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :pickup_venue_id, :binary_id
    field :picked_up_at, :utc_datetime_usec
    field :picked_up_by, :binary_id

    belongs_to :variant, ProductVariant, foreign_key: :variant_id, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(fulfillment, attrs) do
    fulfillment
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :order_line_id,
      :variant_id,
      :status,
      :pickup_venue_id,
      :picked_up_at,
      :picked_up_by
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :order_line_id, :status])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :order_line_id])
  end

  @doc "The possible fulfillment statuses."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses
end
