defmodule SportsCoachBookings.Catalog.Offering do
  @moduledoc "A class type a tenant sells (private, semi-private, or group)."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @formats [:private, :semi_private, :group]

  schema "offerings" do
    field :tenant_id, :binary_id
    field :name, :string
    field :slug, :string
    field :description, :string
    field :format, Ecto.Enum, values: @formats
    field :min_age, :integer
    field :max_age, :integer
    field :duration_minutes, :integer
    field :default_capacity, :integer, default: 1
    field :credit_cost, :integer, default: 1
    field :drop_in_price, :integer
    field :taxable, :boolean, default: false
    field :bookable_until_minutes_before, :integer, default: 60
    field :bookable_from_days_ahead, :integer
    field :active, :boolean, default: true
    field :position, :integer, default: 0
    field :image_key, :string

    timestamps()
  end

  @doc false
  def changeset(offering, attrs) do
    offering
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :slug,
      :description,
      :format,
      :min_age,
      :max_age,
      :duration_minutes,
      :default_capacity,
      :credit_cost,
      :drop_in_price,
      :taxable,
      :bookable_until_minutes_before,
      :bookable_from_days_ahead,
      :active,
      :position,
      :image_key
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :format, :duration_minutes])
    |> Ecto.Changeset.validate_number(:duration_minutes, greater_than: 0)
    |> Ecto.Changeset.validate_number(:default_capacity, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:credit_cost, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:min_age, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:max_age, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:position, greater_than_or_equal_to: 0)
    |> default_slug()
    |> Ecto.Changeset.unique_constraint([:tenant_id, :slug])
  end

  @doc false
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  def slugify(_), do: "offering"

  defp default_slug(changeset) do
    case Ecto.Changeset.get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        changeset

      _ ->
        case Ecto.Changeset.get_field(changeset, :name) do
          name when is_binary(name) -> Ecto.Changeset.put_change(changeset, :slug, slugify(name))
          _ -> changeset
        end
    end
  end
end
