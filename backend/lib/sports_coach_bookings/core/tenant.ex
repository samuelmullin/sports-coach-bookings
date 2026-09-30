defmodule SportsCoachBookings.Core.Tenant do
  @moduledoc """
  A coaching provider (tenant). This is the minimal foundation schema owned by
  WP-00; WP-01 extends it (settings, currency lock, deletion) and adds the
  associated branding.
  """

  use SportsCoachBookings.Core.Schema

  @type t :: %__MODULE__{}

  schema "tenants" do
    field :name, :string
    field :slug, :string
    field :status, Ecto.Enum, values: [:active, :deleted], default: :active
    field :timezone, :string, default: "America/Toronto"
    field :currency, :string, default: "CAD"
    field :contact_email, :string

    has_many :domains, SportsCoachBookings.Core.TenantDomain, foreign_key: :tenant_id

    timestamps()
  end

  @doc false
  def changeset(tenant, attrs) do
    tenant
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :status, :timezone, :currency, :contact_email])
    |> Ecto.Changeset.validate_required([:name, :slug])
    |> Ecto.Changeset.unique_constraint(:slug)
  end
end
