defmodule SportsCoachBookings.Policies.OfferingPolicyAssignment do
  @moduledoc """
  Assigns a cancellation policy to an offering, overriding the tenant's default.
  Owned by WP-10. `offering_id` is a cross-context uuid reference to
  `Catalog.offerings` (no foreign key, per `docs/erd.md`).
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Policies.CancellationPolicy

  @type t :: %__MODULE__{}

  schema "offering_policy_assignments" do
    field :tenant_id, :binary_id
    field :offering_id, :binary_id

    belongs_to :cancellation_policy, CancellationPolicy

    timestamps()
  end

  @doc false
  def changeset(assignment, attrs) do
    assignment
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :offering_id, :cancellation_policy_id])
    |> Ecto.Changeset.validate_required([:tenant_id, :offering_id, :cancellation_policy_id])
    |> Ecto.Changeset.unique_constraint([:offering_id])
  end
end
