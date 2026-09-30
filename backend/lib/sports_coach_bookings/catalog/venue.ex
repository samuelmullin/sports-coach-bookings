defmodule SportsCoachBookings.Catalog.Venue do
  @moduledoc "A physical place where coaching sessions happen."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Core.TenantContext

  @type t :: %__MODULE__{}

  @default_timezone "America/Toronto"

  schema "venues" do
    field :tenant_id, :binary_id
    field :name, :string
    field :address_line1, :string
    field :address_line2, :string
    field :city, :string
    field :province, :string
    field :postal_code, :string
    field :country, :string
    field :timezone, :string, default: @default_timezone
    field :notes, :string
    field :map_url, :string
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(venue, attrs) do
    venue
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :address_line1,
      :address_line2,
      :city,
      :province,
      :postal_code,
      :country,
      :timezone,
      :notes,
      :map_url,
      :active
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :timezone])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 200)
    |> default_timezone()
  end

  defp default_timezone(changeset) do
    case Ecto.Changeset.get_field(changeset, :timezone) do
      nil -> Ecto.Changeset.put_change(changeset, :timezone, tenant_timezone())
      "" -> Ecto.Changeset.put_change(changeset, :timezone, tenant_timezone())
      _ -> changeset
    end
  end

  defp tenant_timezone do
    case TenantContext.get_tenant() do
      %{timezone: timezone} when is_binary(timezone) -> timezone
      _ -> @default_timezone
    end
  end
end
