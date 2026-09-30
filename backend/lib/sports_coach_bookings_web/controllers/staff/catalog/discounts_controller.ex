defmodule SportsCoachBookingsWeb.Staff.Catalog.DiscountsController do
  @moduledoc "Staff CRUD for discounts plus the pricing validation preview."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Catalog.Pricing
  alias SportsCoachBookingsWeb.CatalogJSON

  alias SportsCoachBookingsWeb.Schemas.Catalog.{
    DiscountListResponse,
    DiscountRequest,
    DiscountResponse,
    ValidateDiscountRequest,
    ValidateDiscountResponse
  }

  alias SportsCoachBookingsWeb.Staff.Catalog.Helpers

  tags(["staff"])

  operation(:index,
    summary: "List discounts",
    parameters: [active: [in: :query, type: :boolean, required: false]],
    responses: [ok: {"Discounts", "application/json", DiscountListResponse}]
  )

  @doc "GET /api/staff/catalog/discounts"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :discount) do
      filters = Map.take(params, ["active"])
      %{data: data, next_cursor: cursor} = Catalog.page_discounts(filters, params)

      json(conn, CatalogJSON.collection(Enum.map(data, &CatalogJSON.discount/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a discount",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Discount", "application/json", DiscountResponse}]
  )

  @doc "GET /api/staff/catalog/discounts/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :discount),
         {:ok, discount} <- Catalog.fetch_discount(id) do
      json(conn, CatalogJSON.discount(discount))
    end
  end

  operation(:create,
    summary: "Create a discount",
    request_body: {"Discount", "application/json", DiscountRequest},
    responses: [created: {"Discount", "application/json", DiscountResponse}]
  )

  @doc "POST /api/staff/catalog/discounts"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :discount),
         {:ok, discount} <-
           Catalog.create_discount(Helpers.actor(conn), Helpers.body(params, "discount")) do
      conn
      |> put_status(:created)
      |> json(CatalogJSON.discount(discount))
    end
  end

  operation(:update,
    summary: "Update a discount",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Discount", "application/json", DiscountRequest},
    responses: [ok: {"Discount", "application/json", DiscountResponse}]
  )

  @doc "PATCH /api/staff/catalog/discounts/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :discount),
         {:ok, discount} <-
           Catalog.update_discount(Helpers.actor(conn), id, Helpers.body(params, "discount")) do
      json(conn, CatalogJSON.discount(discount))
    end
  end

  operation(:archive,
    summary: "Archive a discount",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Discount", "application/json", DiscountResponse}]
  )

  @doc "POST /api/staff/catalog/discounts/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :discount),
         {:ok, discount} <- Catalog.archive_discount(Helpers.actor(conn), id) do
      json(conn, CatalogJSON.discount(discount))
    end
  end

  operation(:validate,
    summary: "Preview pricing for lines and a discount code",
    request_body: {"Lines", "application/json", ValidateDiscountRequest},
    responses: [ok: {"Pricing preview", "application/json", ValidateDiscountResponse}]
  )

  @doc "POST /api/staff/catalog/discounts/validate"
  def validate(conn, params) do
    with :ok <- Helpers.authorize(conn, :validate_discount, :discount),
         {:ok, result} <-
           Pricing.price_lines(
             params["lines"] || [],
             params["discount_code"],
             params["household_id"]
           ) do
      json(conn, %{
        lines: result.lines,
        discount: result.discount && CatalogJSON.discount(result.discount),
        subtotal: result.subtotal,
        discount_total: result.discount_total,
        tax_total: result.tax_total,
        total: result.total
      })
    end
  end
end
