defmodule SportsCoachBookings.Inventory.Product do
  @moduledoc "A physical product a tenant sells. Owned by WP-08."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Inventory.ProductVariant

  @type t :: %__MODULE__{}

  schema "products" do
    field :tenant_id, :binary_id
    field :name, :string
    field :description, :string
    field :image_keys, {:array, :string}, default: []
    field :taxable, :boolean, default: true
    field :active, :boolean, default: true
    field :visible_in_portal, :boolean, default: true
    field :position, :integer, default: 0

    has_many :variants, ProductVariant, foreign_key: :product_id

    timestamps()
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :description,
      :image_keys,
      :taxable,
      :active,
      :visible_in_portal,
      :position
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :name])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 200)
    |> Ecto.Changeset.validate_number(:position, greater_than_or_equal_to: 0)
  end
end
