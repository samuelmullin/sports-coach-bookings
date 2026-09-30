defmodule SportsCoachBookings.Catalog.DiscountTarget do
  @moduledoc "A specific offering, package, or product a discount is limited to."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "discount_targets" do
    field :tenant_id, :binary_id
    field :target_type, Ecto.Enum, values: [:offering, :package, :product]
    field :target_id, :binary_id
    belongs_to :discount, SportsCoachBookings.Catalog.Discount

    timestamps()
  end

  @doc false
  def changeset(discount_target, attrs) do
    discount_target
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :discount_id, :target_type, :target_id])
    |> Ecto.Changeset.validate_required([:tenant_id, :discount_id, :target_type, :target_id])
    |> Ecto.Changeset.unique_constraint([:discount_id, :target_type, :target_id])
  end
end
