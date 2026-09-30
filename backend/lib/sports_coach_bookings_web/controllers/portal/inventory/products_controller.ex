defmodule SportsCoachBookingsWeb.Portal.Inventory.ProductsController do
  @moduledoc "Public portal shop: product list and detail with availability labels."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.Inventory.Policy
  alias SportsCoachBookingsWeb.InventoryJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Inventory, as: Schemas

  tags(["portal"])

  operation(:index,
    summary: "List products for sale",
    parameters: [
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [ok: {"Products", "application/json", Schemas.public_product_list()}]
  )

  @doc "GET /api/portal/inventory/products"
  def index(conn, params) do
    with :ok <- Policy.authorize(customer_actor(conn), :list_public, :product) do
      filters = %{"active" => true, "visible_in_portal" => true}
      %{data: data, next_cursor: cursor} = Inventory.page_products(filters, params)

      products =
        Enum.map(data, fn product ->
          InventoryJSON.public_product(product, Inventory.product_availability_label(product.id))
        end)

      json(conn, InventoryJSON.collection(products, cursor))
    end
  end

  operation(:show,
    summary: "Get a product with per-variant availability",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Product", "application/json", Schemas.public_product()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/inventory/products/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Policy.authorize(customer_actor(conn), :view_public, :product),
         {:ok, product} <- Inventory.fetch_product(id),
         :ok <- ensure_visible(product) do
      variants =
        product.id
        |> Inventory.list_variants(%{"active" => true})
        |> Enum.map(fn variant ->
          level = Inventory.fetch_stock_level(variant.id)
          InventoryJSON.public_variant(variant, Inventory.availability_label(variant, level))
        end)

      body =
        product
        |> InventoryJSON.public_product(Inventory.product_availability_label(product.id))
        |> Map.put(:variants, variants)

      json(conn, body)
    end
  end

  defp ensure_visible(%{active: true, visible_in_portal: true}), do: :ok
  defp ensure_visible(_product), do: {:error, :not_found}

  defp customer_actor(conn), do: conn.assigns[:current_customer_actor]
end
