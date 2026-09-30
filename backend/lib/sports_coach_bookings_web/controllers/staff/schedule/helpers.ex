defmodule SportsCoachBookingsWeb.Staff.Schedule.Helpers do
  @moduledoc false

  alias SportsCoachBookings.Scheduling.Policy

  @doc "The staff actor assigned to the request, or `nil`."
  @spec actor(Plug.Conn.t()) :: SportsCoachBookings.Core.Policy.actor()
  def actor(conn), do: conn.assigns[:current_staff_actor]

  @doc "Authorises `action` on `resource` for the request's actor."
  @spec authorize(Plug.Conn.t(), atom(), atom()) :: :ok | {:error, :forbidden}
  def authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  @doc "The membership id of the acting staff user, resolving it when needed."
  @spec membership_id(Plug.Conn.t()) :: binary() | nil
  def membership_id(conn) do
    case actor(conn) do
      %{membership: %{id: id}} when is_binary(id) -> id
      %{staff_user_id: staff_user_id} -> active_membership_id(staff_user_id)
      _ -> nil
    end
  end

  @doc "Extracts attributes from a wrapped or flat request body."
  @spec body(map(), String.t()) :: map()
  def body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["id", "cursor", "limit", key])
    end
  end

  defp active_membership_id(staff_user_id) do
    case SportsCoachBookings.Staff.get_active_membership(staff_user_id) do
      %{id: id} -> id
      _ -> nil
    end
  end
end
