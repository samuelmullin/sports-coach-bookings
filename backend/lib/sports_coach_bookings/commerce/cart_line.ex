defmodule SportsCoachBookings.Commerce.CartLine do
  @moduledoc """
  A single line in a cart. Owned by WP-13.

  `type` is `package | product | drop_in`. `ref_id` is polymorphic:
  a package id, a product variant id, or a booking hold id (wp-14).
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Commerce.Cart

  @type t :: %__MODULE__{}

  @types [:package, :product, :drop_in]

  schema "cart_lines" do
    field :tenant_id, :binary_id
    field :type, Ecto.Enum, values: @types
    field :ref_id, :binary_id
    field :quantity, :integer, default: 1

    belongs_to :cart, Cart, foreign_key: :cart_id

    timestamps()
  end

  @doc false
  def changeset(line, attrs) do
    line
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :cart_id, :type, :ref_id, :quantity])
    |> Ecto.Changeset.validate_required([:tenant_id, :cart_id, :type, :ref_id, :quantity])
    |> Ecto.Changeset.validate_number(:quantity, greater_than: 0)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :cart_id, :type, :ref_id],
      name: :cart_lines_unique_ref
    )
  end
end
