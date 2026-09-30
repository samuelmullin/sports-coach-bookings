defmodule SportsCoachBookingsWeb.Staff.Inventory.VariantsController do
  @moduledoc "Staff CRUD for product variants."

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
    summary: "List a product's variants",
    parameters: [
      product_id: [in: :path, type: :string, required: true],
      active: [in: :query, type: :boolean, required: false]
    ],
    responses: [
      ok: {"Variants", "application/json", Schemas.variant_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/inventory/products/:product_id/variants"
  def index(conn, %{"product_id" => product_id} = params) do
    with :ok <- Helpers.authorize(conn, :list_variants, :product_variant) do
      %{data: data, next_cursor: cursor} =
        Inventory.page_variants(product_id, Map.take(params, ["active"]), params)

      json(conn, InventoryJSON.collection(Enum.map(data, &InventoryJSON.variant/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a variant",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Variant", "application/json", Schemas.variant()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/inventory/variants/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :product_variant),
         {:ok, variant} <- Inventory.fetch_variant(id) do
      json(conn, InventoryJSON.variant(variant))
    end
  end

  operation(:create,
    summary: "Create a variant",
    parameters: [product_id: [in: :path, type: :string, required: true]],
    request_body: {"Variant", "application/json", Schemas.variant_request()},
    responses: [
      created: {"Variant", "application/json", Schemas.variant()},
      not_found: {"Product not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/products/:product_id/variants"
  def create(conn, %{"product_id" => product_id} = params) do
    with :ok <- Helpers.authorize(conn, :create, :product_variant),
         {:ok, variant} <-
           Inventory.create_variant(
             Helpers.actor(conn),
             product_id,
             Helpers.body(params, "variant")
           ) do
      conn
      |> put_status(:created)
      |> json(InventoryJSON.variant(variant))
    end
  end

  operation(:update,
    summary: "Update a variant",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Variant", "application/json", Schemas.variant_request()},
    responses: [
      ok: {"Variant", "application/json", Schemas.variant()},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/inventory/variants/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :product_variant),
         {:ok, variant} <-
           Inventory.update_variant(Helpers.actor(conn), id, Helpers.body(params, "variant")) do
      json(conn, InventoryJSON.variant(variant))
    end
  end

  operation(:archive,
    summary: "Archive a variant",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Variant", "application/json", Schemas.variant()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/variants/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :product_variant),
         {:ok, variant} <- Inventory.archive_variant(Helpers.actor(conn), id) do
      json(conn, InventoryJSON.variant(variant))
    end
  end
end
