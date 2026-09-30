defmodule SportsCoachBookings.Catalog.Discount do
  @moduledoc "A code or automatic discount that applies to catalog lines."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @kinds [:percent, :fixed]
  @applies_to [:all, :packages, :drop_ins, :products]

  schema "discounts" do
    field :tenant_id, :binary_id
    field :code, :string
    field :kind, Ecto.Enum, values: @kinds
    field :value, :integer
    field :applies_to, Ecto.Enum, values: @applies_to, default: :all
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :max_redemptions, :integer
    field :per_household_limit, :integer
    field :min_subtotal, :integer
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(discount, attrs) do
    discount
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :code,
      :kind,
      :value,
      :applies_to,
      :starts_at,
      :ends_at,
      :max_redemptions,
      :per_household_limit,
      :min_subtotal,
      :active
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :kind, :value])
    |> Ecto.Changeset.validate_number(:value, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:max_redemptions, greater_than: 0)
    |> Ecto.Changeset.validate_number(:per_household_limit, greater_than: 0)
    |> Ecto.Changeset.validate_number(:min_subtotal, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :code])
  end
end
