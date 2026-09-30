defmodule SportsCoachBookings.Catalog.Package do
  @moduledoc "A purchasable bundle of credits, optionally limited to offerings."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "packages" do
    field :tenant_id, :binary_id
    field :name, :string
    field :description, :string
    field :credit_quantity, :integer
    field :validity_days, :integer
    field :price, :integer
    field :taxable, :boolean, default: false
    field :per_household_limit, :integer
    field :active, :boolean, default: true
    field :visible_in_portal, :boolean, default: true
    field :position, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(package, attrs) do
    package
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :description,
      :credit_quantity,
      :validity_days,
      :price,
      :taxable,
      :per_household_limit,
      :active,
      :visible_in_portal,
      :position
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :credit_quantity, :price])
    |> Ecto.Changeset.validate_number(:credit_quantity, greater_than: 0)
    |> Ecto.Changeset.validate_number(:price, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:validity_days, greater_than: 0)
    |> Ecto.Changeset.validate_number(:per_household_limit, greater_than: 0)
    |> Ecto.Changeset.validate_number(:position, greater_than_or_equal_to: 0)
  end
end
