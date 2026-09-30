defmodule SportsCoachBookings.Inventory.ProductVariant do
  @moduledoc "A purchasable variant of a product (e.g. size + colour). Owned by WP-08."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Inventory.Product
  alias SportsCoachBookings.Inventory.StockLevel

  @type t :: %__MODULE__{}

  schema "product_variants" do
    field :tenant_id, :binary_id
    field :sku, :string
    field :option_values, :map, default: %{}
    field :price, :integer
    field :low_stock_threshold, :integer
    field :active, :boolean, default: true

    belongs_to :product, Product, foreign_key: :product_id, type: :binary_id
    has_many :stock_levels, StockLevel, foreign_key: :variant_id

    timestamps()
  end

  @doc false
  def changeset(variant, attrs) do
    variant
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :product_id,
      :sku,
      :option_values,
      :price,
      :low_stock_threshold,
      :active
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :product_id, :sku, :price])
    |> Ecto.Changeset.validate_length(:sku, min: 1, max: 80)
    |> Ecto.Changeset.validate_number(:price, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:low_stock_threshold, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :sku])
    |> Ecto.Changeset.check_constraint(:price, name: :price_non_negative)
  end
end
