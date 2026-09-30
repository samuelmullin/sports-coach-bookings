defmodule SportsCoachBookings.Catalog.PackageOffering do
  @moduledoc "Join row linking a package to an eligible offering."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "package_offerings" do
    field :tenant_id, :binary_id
    belongs_to :package, SportsCoachBookings.Catalog.Package
    belongs_to :offering, SportsCoachBookings.Catalog.Offering

    timestamps()
  end

  @doc false
  def changeset(package_offering, attrs) do
    package_offering
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :package_id, :offering_id])
    |> Ecto.Changeset.validate_required([:tenant_id, :package_id, :offering_id])
    |> Ecto.Changeset.unique_constraint([:package_id, :offering_id])
  end
end
