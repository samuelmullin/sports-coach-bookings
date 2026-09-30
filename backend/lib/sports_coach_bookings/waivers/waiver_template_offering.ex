defmodule SportsCoachBookings.Waivers.WaiverTemplateOffering do
  @moduledoc "Join row linking an `offerings`-scoped waiver template to an offering."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Waivers.WaiverTemplate

  @type t :: %__MODULE__{}

  schema "waiver_template_offerings" do
    field :tenant_id, :binary_id
    belongs_to :waiver_template, WaiverTemplate
    # Cross-context (Catalog); plain uuid, no FK.
    field :offering_id, :binary_id

    timestamps()
  end

  @doc false
  def changeset(join, attrs) do
    join
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :waiver_template_id, :offering_id])
    |> Ecto.Changeset.validate_required([:tenant_id, :waiver_template_id, :offering_id])
    |> Ecto.Changeset.unique_constraint([:waiver_template_id, :offering_id])
  end
end
