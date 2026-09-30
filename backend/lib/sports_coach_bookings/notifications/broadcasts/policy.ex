defmodule SportsCoachBookings.Notifications.Broadcasts.Policy do
  @moduledoc """
  Authorization for broadcast messaging. Owned by WP-17.

  | Actor | Manage broadcasts |
  |---|---|
  | Owner / admin | Yes (their tenant) |
  | Coach | No |
  | Customer | No |
  | Anonymous | No |

  Coaches may not broadcast. Controllers call this before any `Broadcasts`
  function.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast

  @manager_actions [
    :list,
    :view,
    :create,
    :update,
    :delete,
    :preview,
    :count_recipients,
    :send_test,
    :schedule,
    :send,
    :cancel,
    :history
  ]

  def authorize(%StaffActor{role: role} = actor, action, resource)
      when role in [:owner, :admin] and action in @manager_actions do
    case resource do
      %Broadcast{tenant_id: tenant_id} -> tenant_ok?(actor, tenant_id)
      _ -> :ok
    end
  end

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands."
  @spec actions() :: [atom()]
  def actions, do: @manager_actions

  defp tenant_ok?(%StaffActor{tenant_id: tenant_id}, tenant_id), do: :ok
  defp tenant_ok?(%StaffActor{}, _other), do: {:error, :forbidden}
end
