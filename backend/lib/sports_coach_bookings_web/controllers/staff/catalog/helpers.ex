defmodule SportsCoachBookingsWeb.Staff.Catalog.Helpers do
  @moduledoc false

  alias SportsCoachBookings.Catalog.Policy

  @doc "The staff actor assigned to the request, or `nil`."
  @spec actor(Plug.Conn.t()) :: SportsCoachBookings.Core.Policy.actor()
  def actor(conn), do: conn.assigns[:current_staff_actor]

  @doc "Authorises `action` on `resource` for the request's actor."
  @spec authorize(Plug.Conn.t(), atom(), atom()) :: :ok | {:error, :forbidden}
  def authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  @doc """
  Extracts the attributes from a request, accepting either a wrapped body
  (`%{"venue" => %{...}}`) or a flat body. Drops routing/query params.
  """
  @spec body(map(), String.t()) :: map()
  def body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["id", "cursor", "limit", key])
    end
  end
end
