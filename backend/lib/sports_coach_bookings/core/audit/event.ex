defmodule SportsCoachBookings.Core.Audit.Event do
  @moduledoc "A single audit-trail entry. Append-only."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "audit_events" do
    field :tenant_id, :binary_id
    field :actor_type, :string
    field :actor_id, :binary_id
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :metadata, :map, default: %{}

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :actor_type,
      :actor_id,
      :action,
      :resource_type,
      :resource_id,
      :metadata
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :action])
  end
end
