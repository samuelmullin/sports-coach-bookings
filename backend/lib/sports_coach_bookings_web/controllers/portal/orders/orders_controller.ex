defmodule SportsCoachBookingsWeb.Portal.Orders.OrdersController do
  @moduledoc "Portal: the caller household's order history and detail."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Commerce.Policy
  alias SportsCoachBookingsWeb.CommerceJSON
  alias SportsCoachBookingsWeb.Schemas.Commerce, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:index,
    summary: "List the caller household's orders",
    parameters: [
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Orders", "application/json", Schemas.order_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/orders"
  def index(conn, params) do
    with :ok <- authorize(conn, :list_own_orders, :order) do
      %{data: data, next_cursor: cursor} =
        Commerce.page_household_orders(household_id(conn), Map.take(params, ["cursor", "limit"]))

      json(conn, CommerceJSON.collection(Enum.map(data, &CommerceJSON.order/1), cursor))
    end
  end

  operation(:show,
    summary: "Get one of the caller household's orders",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Order", "application/json", Schemas.order()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/orders/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- authorize(conn, :view_own_order, :order),
         {:ok, order} <- Commerce.fetch_household_order(household_id(conn), id) do
      json(conn, CommerceJSON.order(order))
    end
  end

  defp authorize(conn, action, resource) do
    Policy.authorize(conn.assigns[:current_customer_actor], action, resource)
  end

  defp household_id(conn), do: conn.assigns[:current_customer_actor].household_id
end
