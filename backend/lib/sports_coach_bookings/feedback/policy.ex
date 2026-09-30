defmodule SportsCoachBookings.Feedback.Policy do
  @moduledoc """
  Authorization for coach feedback and skill tags. Owned by WP-15.

  | Actor | Feedback (own sessions) | Feedback review (all) | Skill tags | Shared feedback for own player |
  |---|---|---|---|---|
  | Owner / admin | Yes | Yes | Read + manage | — |
  | Coach | Yes (assigned sessions only) | — | Read | — |
  | Household manager | — | — | — | Yes |
  | Anonymous | No | No | No | No |

  Role gating happens here. The context enforces resource scoping: a coach may
  only read/submit feedback for sessions they are assigned to (via
  `Scheduling.session_detail/1`) and for players visible via
  `Bookings.CoachAccess` (routed through the configurable `:coach_access`
  module so tests can exercise both outcomes). The session-scope check is a
  context concern, exactly as in `Bookings.Policy`.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players.Player

  @manager_actions [
    :list,
    :get,
    :create,
    :share,
    :edit,
    :review,
    :roster,
    :mark_attendance,
    :list_skill_tags,
    :manage_skill_tags
  ]

  @coach_actions [
    :list,
    :get,
    :create,
    :share,
    :edit,
    :roster,
    :mark_attendance,
    :list_skill_tags
  ]

  @resources [:feedback, :skill_tag]

  ## Owner / admin: full control of feedback and skill tags within the tenant.

  def authorize(%StaffActor{role: role}, action, _resource)
      when role in [:owner, :admin] and action in @manager_actions,
      do: :ok

  ## Coach: read/submit feedback, but only for their own sessions and visible
  ## players (enforced by the context).

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in @coach_actions and resource in @resources,
      do: :ok

  def authorize(%StaffActor{role: :coach} = actor, action, %Player{} = player)
      when action in [:list, :get] do
    if player_visible?(actor, player.id), do: :ok, else: {:error, :forbidden}
  end

  ## Household manager: shared feedback about a player in their own household.

  def authorize(%CustomerActor{} = actor, :list_shared, %Player{} = player) do
    if owns?(actor, player), do: :ok, else: {:error, :forbidden}
  end

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "Every action the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions do
    Enum.uniq(@manager_actions ++ @coach_actions ++ [:list_shared])
  end

  @doc "The resources the policy understands. Used by tests and tooling."
  @spec resources() :: [atom()]
  def resources, do: @resources

  @doc "The actions a coach is allowed."
  @spec coach_actions() :: [atom()]
  def coach_actions, do: @coach_actions

  @doc "The actions only an owner or admin may perform."
  @spec manager_actions() :: [atom()]
  def manager_actions, do: @manager_actions

  defp owns?(
         %CustomerActor{household_id: household_id, tenant_id: tenant_id},
         %Player{household_id: household_id, tenant_id: tenant_id}
       ),
       do: true

  defp owns?(_actor, _player), do: false

  defp player_visible?(actor, player_id) do
    coach_access().player_visible?(actor, player_id)
  end

  defp coach_access do
    Application.get_env(
      :sports_coach_bookings,
      :coach_access,
      SportsCoachBookings.Bookings.CoachAccess
    )
  end
end
