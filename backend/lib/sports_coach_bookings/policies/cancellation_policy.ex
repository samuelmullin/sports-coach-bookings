defmodule SportsCoachBookings.Policies.CancellationPolicy do
  @moduledoc """
  A tenant's cancellation/rebooking policy. Owned by WP-10.

  Exactly one policy per tenant is the `is_default` policy (enforced by a partial
  unique index). Editing a policy bumps its `version`; bookings keep the snapshot
  taken when they were created, so a later edit never changes an existing
  booking's terms.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Policies.Rules

  @type t :: %__MODULE__{}

  schema "cancellation_policies" do
    field :tenant_id, :binary_id
    field :name, :string
    field :is_default, :boolean, default: false
    field :version, :integer, default: 1
    field :active, :boolean, default: true
    field :customer_facing_summary, :string

    embeds_one :rules, Rules, on_replace: :update

    timestamps()
  end

  @doc false
  def changeset(policy, attrs) do
    policy
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :is_default,
      :active,
      :customer_facing_summary
    ])
    |> Ecto.Changeset.cast_embed(:rules, required: true)
    |> Ecto.Changeset.validate_required([:tenant_id, :name])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 200)
  end
end
