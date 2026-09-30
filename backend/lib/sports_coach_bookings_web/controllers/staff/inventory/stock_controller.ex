defmodule SportsCoachBookingsWeb.Staff.Inventory.StockController do
  @moduledoc "Staff stock receiving, adjustment, levels, and movement history."

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
    summary: "List stock levels",
    parameters: [
      variant_id: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Stock levels", "application/json", Schemas.stock_level_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/inventory/stock_levels"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list_stock_levels, :stock_level) do
      levels = Inventory.list_stock_levels(Map.take(params, ["variant_id"]))
      json(conn, InventoryJSON.collection(Enum.map(levels, &InventoryJSON.stock_level/1)))
    end
  end

  operation(:receive,
    summary: "Receive stock for a variant",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Receipt", "application/json", Schemas.stock_receive_request()},
    responses: [
      created: {"Movement", "application/json", Schemas.stock_movement()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/variants/:id/stock/receive"
  def receive(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :receive_stock, :stock_level),
         {:ok, movement} <-
           Inventory.receive_stock(Helpers.actor(conn), id, Helpers.body(params, "receipt")) do
      conn
      |> put_status(:created)
      |> json(InventoryJSON.movement(movement))
    end
  end

  operation(:adjust,
    summary: "Adjust a variant's stock",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Adjustment", "application/json", Schemas.stock_adjust_request()},
    responses: [
      created: {"Movement", "application/json", Schemas.stock_movement()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/variants/:id/stock/adjust"
  def adjust(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :adjust_stock, :stock_level),
         {:ok, movement} <-
           Inventory.adjust_stock(Helpers.actor(conn), id, Helpers.body(params, "adjustment")) do
      conn
      |> put_status(:created)
      |> json(InventoryJSON.movement(movement))
    end
  end

  operation(:movements,
    summary: "List a variant's movement history",
    parameters: [
      id: [in: :path, type: :string, required: true],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Movements", "application/json", Schemas.stock_movement_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/inventory/variants/:id/stock/movements"
  def movements(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :list_movements, :stock_movement) do
      %{data: data, next_cursor: cursor} = Inventory.page_movements(id, params)
      json(conn, InventoryJSON.collection(Enum.map(data, &InventoryJSON.movement/1), cursor))
    end
  end
end
