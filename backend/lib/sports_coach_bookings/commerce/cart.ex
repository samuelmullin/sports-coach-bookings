defmodule SportsCoachBookings.Commerce.Cart do
  @moduledoc """
  A customer's in-progress basket. Owned by WP-13.

  A cart belongs to one household in the resolved tenant and holds `cart_lines`.
  `discount_code` is the code the customer has applied; it is validated and
  priced at checkout time (never trusted as a price).
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Commerce.CartLine

  @type t :: %__MODULE__{}

  schema "carts" do
    field :tenant_id, :binary_id
    field :household_id, :binary_id
    field :discount_code, :string
    field :expires_at, :utc_datetime_usec

    has_many :lines, CartLine, foreign_key: :cart_id

    timestamps()
  end

  @doc false
  def changeset(cart, attrs) do
    cart
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :household_id, :discount_code, :expires_at])
    |> Ecto.Changeset.validate_required([:tenant_id, :household_id])
  end
end
