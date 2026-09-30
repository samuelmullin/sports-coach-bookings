defmodule SportsCoachBookings.Waivers.WaiverTemplate do
  @moduledoc """
  A versioned waiver/release. Owned by WP-07.

  `scope` is either `:all_bookings` (required for every booking) or
  `:offerings` (required only for the offerings linked through
  `waiver_template_offerings`).
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Waivers.WaiverTemplateOffering
  alias SportsCoachBookings.Waivers.WaiverVersion

  @type t :: %__MODULE__{}

  @scopes [:all_bookings, :offerings]

  schema "waiver_templates" do
    field :tenant_id, :binary_id
    field :name, :string
    field :scope, Ecto.Enum, values: @scopes
    field :require_resign_on_new_version, :boolean, default: false
    field :active, :boolean, default: true

    has_many :template_offerings, WaiverTemplateOffering, foreign_key: :waiver_template_id
    has_many :versions, WaiverVersion, foreign_key: :waiver_template_id

    timestamps()
  end

  @doc false
  def changeset(template, attrs) do
    template
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :scope,
      :require_resign_on_new_version,
      :active
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :scope])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 200)
  end
end
