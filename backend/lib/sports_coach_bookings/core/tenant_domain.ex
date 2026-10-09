defmodule SportsCoachBookings.Core.TenantDomain do
  @moduledoc """
  Maps a platform subdomain or manually commissioned custom hostname to a tenant.
  """

  use SportsCoachBookings.Core.Schema

  @type t :: %__MODULE__{}

  schema "tenant_domains" do
    field :host, :string
    field :primary, :boolean, default: false

    belongs_to :tenant, SportsCoachBookings.Core.Tenant, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(domain, attrs) do
    domain
    |> Ecto.Changeset.cast(attrs, [:host, :primary])
    |> Ecto.Changeset.validate_required([:host])
    |> Ecto.Changeset.unique_constraint(:host)
  end
end
