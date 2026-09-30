defmodule SportsCoachBookingsWeb.Staff.Catalog.TaxRatesController do
  @moduledoc "Staff CRUD for tax rates."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookingsWeb.CatalogJSON

  alias SportsCoachBookingsWeb.Schemas.Catalog.{
    TaxRateListResponse,
    TaxRateRequest,
    TaxRateResponse
  }

  alias SportsCoachBookingsWeb.Staff.Catalog.Helpers

  tags(["staff"])

  operation(:index,
    summary: "List tax rates",
    parameters: [active: [in: :query, type: :boolean, required: false]],
    responses: [ok: {"Tax rates", "application/json", TaxRateListResponse}]
  )

  @doc "GET /api/staff/catalog/tax_rates"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :tax_rate) do
      filters = Map.take(params, ["active"])
      %{data: data, next_cursor: cursor} = Catalog.page_tax_rates(filters, params)

      json(conn, CatalogJSON.collection(Enum.map(data, &CatalogJSON.tax_rate/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a tax rate",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Tax rate", "application/json", TaxRateResponse}]
  )

  @doc "GET /api/staff/catalog/tax_rates/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :tax_rate),
         {:ok, tax_rate} <- Catalog.fetch_tax_rate(id) do
      json(conn, CatalogJSON.tax_rate(tax_rate))
    end
  end

  operation(:create,
    summary: "Create a tax rate",
    request_body: {"Tax rate", "application/json", TaxRateRequest},
    responses: [created: {"Tax rate", "application/json", TaxRateResponse}]
  )

  @doc "POST /api/staff/catalog/tax_rates"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :tax_rate),
         {:ok, tax_rate} <-
           Catalog.create_tax_rate(Helpers.actor(conn), Helpers.body(params, "tax_rate")) do
      conn
      |> put_status(:created)
      |> json(CatalogJSON.tax_rate(tax_rate))
    end
  end

  operation(:update,
    summary: "Update a tax rate",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Tax rate", "application/json", TaxRateRequest},
    responses: [ok: {"Tax rate", "application/json", TaxRateResponse}]
  )

  @doc "PATCH /api/staff/catalog/tax_rates/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :tax_rate),
         {:ok, tax_rate} <-
           Catalog.update_tax_rate(Helpers.actor(conn), id, Helpers.body(params, "tax_rate")) do
      json(conn, CatalogJSON.tax_rate(tax_rate))
    end
  end

  operation(:archive,
    summary: "Archive a tax rate",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Tax rate", "application/json", TaxRateResponse}]
  )

  @doc "POST /api/staff/catalog/tax_rates/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :tax_rate),
         {:ok, tax_rate} <- Catalog.archive_tax_rate(Helpers.actor(conn), id) do
      json(conn, CatalogJSON.tax_rate(tax_rate))
    end
  end
end
