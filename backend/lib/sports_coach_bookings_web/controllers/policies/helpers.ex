defmodule SportsCoachBookingsWeb.Policies.Helpers do
  @moduledoc false

  alias SportsCoachBookings.Policies.Policy

  @doc "The authenticated actor (staff or customer) assigned to the request."
  @spec actor(Plug.Conn.t()) :: SportsCoachBookings.Core.Policy.actor()
  def actor(conn),
    do: conn.assigns[:current_staff_actor] || conn.assigns[:current_customer_actor]

  @doc "Authorises `action` on `resource` for the request's actor."
  @spec authorize(Plug.Conn.t(), atom(), term()) :: :ok | {:error, :forbidden}
  def authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  @doc """
  Extracts attributes from a request, accepting either a wrapped body
  (`%{"policy" => %{...}}`) or a flat body. Drops routing/query params.
  """
  @spec body(map(), String.t()) :: map()
  def body(params, key) do
    case Map.get(params, key) do
      %{} = attrs ->
        attrs

      _ ->
        Map.drop(params, ["id", "offering_id", "cursor", "limit", key])
    end
  end

  @doc "The `offering_ids` list from an assignment request body."
  @spec offering_ids(map()) :: [binary()]
  def offering_ids(params) do
    case Map.get(params, "offering_ids") do
      ids when is_list(ids) -> Enum.filter(ids, &is_binary/1)
      _ -> []
    end
  end
end
