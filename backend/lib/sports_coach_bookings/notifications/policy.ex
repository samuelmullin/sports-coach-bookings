defmodule SportsCoachBookings.Notifications.Policy do
  @moduledoc """
  Authorization for notification administration. Owned by WP-05.

  | Actor | Delivery log | Resend a delivery | Own preferences |
  |---|---|---|---|
  | Owner / admin | Yes (their tenant) | Yes (their tenant) | Yes |
  | Coach | No | No | Yes |
  | Customer | No | No | Yes |
  | Anonymous | No | No | No |

  Controllers call this before any `Notifications` function.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Notifications.Delivery

  @admin_actions [:view_delivery_log, :resend_delivery]
  @preference_actions [:view_preferences, :update_preferences]

  ## Owner / admin

  def authorize(%StaffActor{role: role}, action, :notifications)
      when role in [:owner, :admin] and action in @admin_actions,
      do: :ok

  def authorize(%StaffActor{role: role} = actor, action, %Delivery{} = delivery)
      when role in [:owner, :admin] and action in @admin_actions do
    tenant_ok?(actor, delivery)
  end

  ## Preferences (any authenticated actor manages their own)

  def authorize(%StaffActor{}, action, :preferences) when action in @preference_actions, do: :ok

  def authorize(%CustomerActor{}, action, :preferences) when action in @preference_actions,
    do: :ok

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions, do: Enum.uniq(@admin_actions ++ @preference_actions)

  defp tenant_ok?(%StaffActor{tenant_id: tenant_id}, %Delivery{tenant_id: tenant_id}), do: :ok
  defp tenant_ok?(%StaffActor{}, _delivery), do: {:error, :forbidden}
end
