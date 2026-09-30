defmodule SportsCoachBookings.Scheduling.Policy do
  @moduledoc """
  Authorization for scheduling. Owned by WP-11.

  | Actor | Sessions / series (staff) | Calendar (staff) | Portal calendar |
  |---|---|---|---|
  | Owner / admin | Full control | Read | Read |
  | Coach | Read own sessions | Read | Read |
  | Customer / anonymous | — | — | Read public, bookable sessions |

  A coach's staff-level reads are further scoped by the context (only sessions
  they are assigned to) — the policy only decides that coaches may read.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor

  @staff_manage_actions [
    :list,
    :get,
    :create,
    :update,
    :cancel,
    :reschedule,
    :edit_series,
    :create_series
  ]
  @staff_read_actions [:list, :get, :my_sessions]
  @staff_resources [:session, :session_series, :calendar]
  @portal_actions [:list_public, :get_public]
  @portal_resources [:session, :calendar]

  def authorize(%StaffActor{role: role}, action, resource)
      when role in [:owner, :admin] and action in @staff_manage_actions and
             resource in @staff_resources,
      do: :ok

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in @staff_read_actions and resource in @staff_resources,
      do: :ok

  def authorize(_actor, action, resource)
      when action in @portal_actions and resource in @portal_resources,
      do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "Every action the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions do
    Enum.uniq(@staff_manage_actions ++ @staff_read_actions ++ @portal_actions)
  end
end
