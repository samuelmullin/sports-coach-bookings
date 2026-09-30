defmodule SportsCoachBookingsWeb.Staff.Inventory.ProductsController do
  @moduledoc "Staff CRUD and reordering for products."

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
    summary: "List products",
    parameters: [
      active: [in: :query, type: :boolean, required: false],
      visible_in_portal: [in: :query, type: :boolean, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Products", "application/json", Schemas.product_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/inventory/products"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :product) do
      filters = Map.take(params, ["active", "visible_in_portal"])
      %{data: data, next_cursor: cursor} = Inventory.page_products(filters, params)

      json(conn, InventoryJSON.collection(Enum.map(data, &InventoryJSON.product/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a product",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Product", "application/json", Schemas.product()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/inventory/products/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :product),
         {:ok, product} <- Inventory.fetch_product(id) do
      json(conn, InventoryJSON.product(product))
    end
  end

  operation(:create,
    summary: "Create a product",
    request_body: {"Product", "application/json", Schemas.product_request()},
    responses: [
      created: {"Product", "application/json", Schemas.product()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/products"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :product),
         {:ok, product} <-
           Inventory.create_product(Helpers.actor(conn), Helpers.body(params, "product")) do
      conn
      |> put_status(:created)
      |> json(InventoryJSON.product(product))
    end
  end

  operation(:update,
    summary: "Update a product",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Product", "application/json", Schemas.product_request()},
    responses: [
      ok: {"Product", "application/json", Schemas.product()},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/inventory/products/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :product),
         {:ok, product} <-
           Inventory.update_product(Helpers.actor(conn), id, Helpers.body(params, "product")) do
      json(conn, InventoryJSON.product(product))
    end
  end

  operation(:archive,
    summary: "Archive a product",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Product", "application/json", Schemas.product()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/products/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :product),
         {:ok, product} <- Inventory.archive_product(Helpers.actor(conn), id) do
      json(conn, InventoryJSON.product(product))
    end
  end

  operation(:reorder,
    summary: "Reorder products",
    request_body: {"Ordered ids", "application/json", Schemas.reorder_request()},
    responses: [
      ok: {"Products", "application/json", Schemas.product_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/products/reorder"
  def reorder(conn, %{"ids" => ids}) do
    with :ok <- Helpers.authorize(conn, :reorder, :product),
         {:ok, products} <- Inventory.reorder_products(Helpers.actor(conn), ids) do
      json(conn, InventoryJSON.collection(Enum.map(products, &InventoryJSON.product/1)))
    end
  end
end
