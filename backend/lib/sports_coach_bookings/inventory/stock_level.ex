defmodule SportsCoachBookings.Inventory.StockLevel do
  @moduledoc """
  On-hand and reserved stock for a variant. Owned by WP-08.

  MVP is single-location, so `venue_id` is `nil`; the column exists for a later
  multi-location rollout. `on_hand` is the sum of non-reservation stock
  movements and `reserved` is the sum of reservation movements.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Inventory.ProductVariant

  @type t :: %__MODULE__{}

  schema "stock_levels" do
    field :tenant_id, :binary_id
    field :on_hand, :integer, default: 0
    field :reserved, :integer, default: 0
    field :venue_id, :binary_id
    field :low_stock_notified_on, :date

    belongs_to :variant, ProductVariant, foreign_key: :variant_id, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(level, attrs) do
    level
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :variant_id, :on_hand, :reserved, :venue_id])
    |> Ecto.Changeset.validate_required([:tenant_id, :variant_id])
    |> Ecto.Changeset.validate_number(:on_hand, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:reserved, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :variant_id, :venue_id])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :variant_id],
      name: :stock_levels_one_per_variant_per_tenant
    )
    |> Ecto.Changeset.check_constraint(:on_hand, name: :stock_non_negative)
  end

  @doc "Available stock: `on_hand - reserved`."
  @spec available(t()) :: integer()
  def available(%__MODULE__{on_hand: on_hand, reserved: reserved}), do: on_hand - reserved
end
