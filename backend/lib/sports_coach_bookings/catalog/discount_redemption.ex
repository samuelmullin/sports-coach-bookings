defmodule SportsCoachBookings.Catalog.DiscountRedemption do
  @moduledoc "Records that a discount was redeemed on an order (idempotent write)."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "discount_redemptions" do
    field :tenant_id, :binary_id
    field :household_id, :binary_id
    field :order_id, :binary_id
    belongs_to :discount, SportsCoachBookings.Catalog.Discount

    timestamps()
  end

  @doc false
  def changeset(redemption, attrs) do
    redemption
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :discount_id, :household_id, :order_id])
    |> Ecto.Changeset.validate_required([:tenant_id, :discount_id, :household_id, :order_id])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :discount_id, :order_id])
  end
end
