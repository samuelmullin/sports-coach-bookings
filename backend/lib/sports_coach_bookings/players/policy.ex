defmodule SportsCoachBookings.Players.Policy do
  @moduledoc """
  Authorization for players, contacts, pickups, and medical data. Owned by WP-06.

  | Actor | Profile / contacts / pickups | Medical |
  |---|---|---|
  | Household manager | Full CRUD for own household's players | Full CRUD |
  | Owner / admin | Read + update | Read (audited) + update (audited) |
  | Coach | Read only if the player is visible via `Bookings.CoachAccess` | Read only if visible (audited) |
  | Other customers | None | None |
  | Anonymous | None | None |

  A coach is only allowed to see a specific player when
  `SportsCoachBookings.Bookings.CoachAccess.player_visible?/2` returns `true`.
  The call is routed through the configurable `:coach_access` module (default:
  that module) so tests can exercise both outcomes.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players.Player

  @manager_actions [
    :list,
    :get,
    :update,
    :read_medical,
    :update_medical,
    :list_position_options,
    :manage_position_options
  ]

  @household_player_actions [:get, :update, :archive, :read_medical, :update_medical]

  ## Owner / admin: read + update everything in the tenant, manage positions.

  def authorize(%StaffActor{role: role} = actor, action, resource)
      when role in [:owner, :admin] and action in @manager_actions do
    if tenant_ok?(actor, resource), do: :ok, else: {:error, :forbidden}
  end

  ## Coach: read a specific player only when they are visible via bookings.

  def authorize(%StaffActor{role: :coach} = actor, action, %Player{} = player)
      when action in [:get, :read_medical] do
    if tenant_ok?(actor, player) and player_visible?(actor, player),
      do: :ok,
      else: {:error, :forbidden}
  end

  def authorize(%StaffActor{role: :coach}, :list_position_options, :position_option), do: :ok

  ## Household manager: full CRUD for own household's players.

  def authorize(%CustomerActor{}, :create, :player), do: :ok

  def authorize(%CustomerActor{}, :list, :player), do: :ok

  def authorize(%CustomerActor{} = actor, action, %Player{} = player)
      when action in @household_player_actions do
    if owns?(actor, player), do: :ok, else: {:error, :forbidden}
  end

  ## Any authenticated actor may read the tenant's position options.

  def authorize(%CustomerActor{}, :list_position_options, :position_option), do: :ok

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The action atoms the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions do
    Enum.uniq(
      @manager_actions ++
        @household_player_actions ++ [:create, :archive, :list_position_options]
    )
  end

  defp owns?(
         %CustomerActor{household_id: household_id, tenant_id: tenant_id},
         %Player{household_id: household_id, tenant_id: tenant_id}
       ),
       do: true

  defp owns?(_actor, _player), do: false

  defp tenant_ok?(%StaffActor{tenant_id: tenant_id}, %Player{tenant_id: tenant_id}),
    do: true

  defp tenant_ok?(%StaffActor{}, %Player{}), do: false

  defp tenant_ok?(%StaffActor{}, _resource), do: true

  defp player_visible?(actor, %Player{id: player_id}) do
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
