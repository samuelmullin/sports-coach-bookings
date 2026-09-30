defmodule SportsCoachBookingsWeb.Waivers.Helpers do
  @moduledoc false

  alias SportsCoachBookings.Waivers.Policy

  @doc "The authenticated actor (staff or customer) assigned to the request."
  @spec actor(Plug.Conn.t()) :: SportsCoachBookings.Core.Policy.actor()
  def actor(conn),
    do: conn.assigns[:current_staff_actor] || conn.assigns[:current_customer_actor]

  @doc "Authorises `action` on `resource` for the request's actor."
  @spec authorize(Plug.Conn.t(), atom(), term()) :: :ok | {:error, :forbidden}
  def authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  @doc """
  Extracts attributes from a request, accepting either a wrapped body
  (`%{"template" => %{...}}`) or a flat body. Drops routing/query params.
  """
  @spec body(map(), String.t()) :: map()
  def body(params, key) do
    case Map.get(params, key) do
      %{} = attrs ->
        attrs

      _ ->
        Map.drop(params, ["id", "player_id", "template_id", "version_id", "cursor", "limit", key])
    end
  end

  @doc "Filters for signature listings from request params."
  @spec signature_filters(map()) :: map()
  def signature_filters(params) do
    Map.take(params, ["player_id", "template_id", "version_id"])
  end

  @doc "The request's remote IP as a string."
  @spec ip(Plug.Conn.t()) :: String.t()
  def ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  @doc "The request's User-Agent header, or `\"unknown\"`."
  @spec user_agent(Plug.Conn.t()) :: String.t()
  def user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] when ua != "" -> ua
      _ -> "unknown"
    end
  end
end
