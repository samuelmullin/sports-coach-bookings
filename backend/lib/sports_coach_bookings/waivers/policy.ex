defmodule SportsCoachBookings.Waivers.Policy do
  @moduledoc """
  Authorization for waivers, versions, and signatures. Owned by WP-07.

  | Actor | Templates / versions | Signatures | Portal (own household) |
  |---|---|---|---|
  | Owner / admin | Full CRUD, publish | Read + download | — |
  | Coach | Read + preview | Read + download | — |
  | Household manager | — | — | View + sign for own players, read published bodies, download own PDFs |
  | Other customers | — | — | None |
  | Anonymous | — | — | None |

  Portal actions operating on a specific player (`:list_player_waivers`, `:sign`,
  `:download_pdf`) are allowed only when the player belongs to the caller's
  household.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players.Player

  @staff_read_resources [:waiver_template, :waiver_version, :waiver_signature]
  @staff_read_actions [:list, :get, :preview, :list_signatures, :download_pdf]

  ## Owner / admin: full control within their tenant.

  def authorize(%StaffActor{role: role} = actor, _action, resource)
      when role in [:owner, :admin] do
    if resource_tenant_ok?(actor, resource), do: :ok, else: {:error, :forbidden}
  end

  ## Coach: read-only.

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in @staff_read_actions and resource in @staff_read_resources,
      do: :ok

  ## Household manager: own household only.

  def authorize(%CustomerActor{}, :status, :waiver_status), do: :ok

  def authorize(%CustomerActor{}, :view_version, :waiver_version), do: :ok

  def authorize(%CustomerActor{} = actor, action, %Player{} = player)
      when action in [:list_player_waivers, :sign, :download_pdf] do
    if owns?(actor, player), do: :ok, else: {:error, :forbidden}
  end

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions do
    Enum.uniq(
      @staff_read_actions ++
        [:create, :update, :archive, :publish, :status, :view_version, :sign]
    )
  end

  defp owns?(
         %CustomerActor{household_id: household_id, tenant_id: tenant_id},
         %Player{household_id: household_id, tenant_id: tenant_id}
       ),
       do: true

  defp owns?(_actor, _player), do: false

  defp resource_tenant_ok?(%StaffActor{tenant_id: tenant_id}, %Player{tenant_id: tenant_id}),
    do: true

  defp resource_tenant_ok?(%StaffActor{}, %Player{}), do: false

  defp resource_tenant_ok?(%StaffActor{}, _resource), do: true
end
