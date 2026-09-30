defmodule SportsCoachBookings.Core.Audit do
  @moduledoc """
  Append-only audit trail.

  Call `record/4` for every admin write, every medical-data read, every
  refund/adjustment, and every role change. It must run inside the same
  transaction as the state change it describes (it relies on the tenant GUC for
  the RLS policy on `audit_events`).
  """

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Repo

  @doc """
  Records an audit event for `actor` performing `action` against `resource`.

  `action` is a dotted snake_case string such as `"staff.role_changed"`.
  `metadata` must be JSON-serialisable and must never contain secrets or raw
  medical values.
  """
  @spec record(
          SportsCoachBookings.Core.Policy.actor(),
          atom() | String.t(),
          struct() | nil,
          map()
        ) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def record(actor, action, resource \\ nil, metadata \\ %{}) do
    {actor_type, actor_id} = actor_fields(actor)
    {resource_type, resource_id} = resource_fields(resource)

    attrs = %{
      tenant_id: TenantContext.get_tenant_id(),
      actor_type: actor_type,
      actor_id: actor_id,
      action: to_string(action),
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    }

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  defp actor_fields(nil), do: {nil, nil}

  defp actor_fields(%StaffActor{staff_user_id: id}), do: {"StaffActor", id}

  defp actor_fields(%CustomerActor{customer_user_id: id}), do: {"CustomerActor", id}

  defp resource_fields(nil), do: {nil, nil}

  defp resource_fields(%{__struct__: module} = resource) do
    {inspect(module), Map.get(resource, :id)}
  end

  defp resource_fields(_), do: {nil, nil}
end
