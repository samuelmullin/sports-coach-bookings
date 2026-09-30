defmodule SportsCoachBookingsWeb.Staff.Inventory.Helpers do
  @moduledoc false

  alias SportsCoachBookings.Inventory.Policy

  @doc "The staff actor assigned to the request, or `nil`."
  @spec actor(Plug.Conn.t()) :: SportsCoachBookings.Core.Policy.actor()
  def actor(conn), do: conn.assigns[:current_staff_actor]

  @doc "Authorises `action` on `resource` for the request's actor."
  @spec authorize(Plug.Conn.t(), atom(), atom()) :: :ok | {:error, :forbidden}
  def authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  @doc """
  Extracts attributes from a request, accepting either a wrapped body
  (`%{"product" => %{...}}`) or a flat body. Drops routing/query params.
  """
  @spec body(map(), String.t()) :: map()
  def body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["id", "cursor", "limit", "product_id", key])
    end
  end
end
