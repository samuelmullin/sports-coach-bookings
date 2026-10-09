defmodule SportsCoachBookings.Websites.Site do
  @moduledoc "A tenant's draft and published hosted-website content."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "website_sites" do
    field :tenant_id, :binary_id
    field :enabled, :boolean, default: true
    field :draft_content, :map, default: %{}
    field :published_content, :map, default: %{}
    field :published_at, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :enabled,
      :draft_content,
      :published_content,
      :published_at
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :enabled,
      :draft_content,
      :published_content
    ])
    |> Ecto.Changeset.unique_constraint(:tenant_id,
      name: :website_sites_tenant_unique_index
    )
  end
end
