defmodule SportsCoachBookingsWeb.Customers.Helpers do
  @moduledoc false

  @doc "The authenticated customer actor assigned to the request (or `nil`)."
  @spec actor(Plug.Conn.t()) :: SportsCoachBookings.Core.CustomerActor.t() | nil
  def actor(conn), do: conn.assigns[:current_customer_actor]

  @doc "The authenticated customer user assigned to the request (or `nil`)."
  @spec customer_user(Plug.Conn.t()) :: SportsCoachBookings.Customers.CustomerUser.t() | nil
  def customer_user(conn), do: conn.assigns[:current_customer_user]

  @doc """
  Extracts attributes from a request, accepting either a wrapped body
  (`%{"customer" => %{...}}`) or a flat body. Drops routing/query params.
  """
  @spec body(map(), String.t(), [String.t()]) :: map()
  def body(params, key, drop \\ []) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["token", "id", "cursor", "limit", key | drop])
    end
  end
end
