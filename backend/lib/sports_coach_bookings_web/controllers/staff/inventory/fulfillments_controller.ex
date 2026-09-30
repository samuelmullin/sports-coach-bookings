defmodule SportsCoachBookingsWeb.Staff.Inventory.FulfillmentsController do
  @moduledoc "Staff pickup queue: list, mark ready, and mark picked up."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Inventory
  alias SportsCoachBookingsWeb.InventoryJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Inventory, as: Schemas
  alias SportsCoachBookingsWeb.Staff.Inventory.Helpers

  tags(["staff"])

  operation(:index,
    summary: "List fulfillments (pickup queue)",
    parameters: [
      status: [
        in: :query,
        type: :string,
        required: false
      ],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Fulfillments", "application/json", Schemas.fulfillment_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/inventory/fulfillments"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list_fulfillments, :fulfillment) do
      %{data: data, next_cursor: cursor} =
        Inventory.page_fulfillments(Map.take(params, ["status"]), params)

      json(conn, InventoryJSON.collection(Enum.map(data, &InventoryJSON.fulfillment/1), cursor))
    end
  end

  operation(:ready,
    summary: "Mark a fulfillment ready for pickup",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Fulfillment", "application/json", Schemas.fulfillment()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/fulfillments/:id/ready"
  def ready(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :mark_ready, :fulfillment),
         {:ok, fulfillment} <- Inventory.mark_ready(Helpers.actor(conn), id) do
      json(conn, InventoryJSON.fulfillment(fulfillment))
    end
  end

  operation(:pickup,
    summary: "Mark a fulfillment picked up",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Fulfillment", "application/json", Schemas.fulfillment()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/fulfillments/:id/pickup"
  def pickup(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :mark_picked_up, :fulfillment),
         {:ok, fulfillment} <-
           Inventory.mark_picked_up(Helpers.actor(conn), id, Helpers.body(params, "pickup")) do
      json(conn, InventoryJSON.fulfillment(fulfillment))
    end
  end
end
