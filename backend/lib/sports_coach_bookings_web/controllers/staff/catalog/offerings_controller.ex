defmodule SportsCoachBookingsWeb.Staff.Catalog.OfferingsController do
  @moduledoc "Staff CRUD and reordering for offerings."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookingsWeb.CatalogJSON

  alias SportsCoachBookingsWeb.Schemas.Catalog.{
    OfferingListResponse,
    OfferingRequest,
    OfferingResponse,
    ReorderRequest
  }

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Staff.Catalog.Helpers

  tags(["staff"])

  operation(:index,
    summary: "List offerings",
    parameters: [
      active: [in: :query, type: :boolean, required: false],
      format: [in: :query, type: :string, required: false],
      age: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Offerings", "application/json", OfferingListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/catalog/offerings"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :offering) do
      filters = params |> Map.take(["active", "format", "age"]) |> parse_age()
      %{data: data, next_cursor: cursor} = Catalog.page_offerings(filters, params)

      json(conn, CatalogJSON.collection(Enum.map(data, &CatalogJSON.offering/1), cursor))
    end
  end

  operation(:show,
    summary: "Get an offering",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Offering", "application/json", OfferingResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/catalog/offerings/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :offering),
         {:ok, offering} <- Catalog.fetch_offering(id) do
      json(conn, CatalogJSON.offering(offering))
    end
  end

  operation(:create,
    summary: "Create an offering",
    request_body: {"Offering", "application/json", OfferingRequest},
    responses: [
      created: {"Offering", "application/json", OfferingResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/catalog/offerings"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :offering),
         {:ok, offering} <-
           Catalog.create_offering(Helpers.actor(conn), Helpers.body(params, "offering")) do
      conn
      |> put_status(:created)
      |> json(CatalogJSON.offering(offering))
    end
  end

  operation(:update,
    summary: "Update an offering",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Offering", "application/json", OfferingRequest},
    responses: [
      ok: {"Offering", "application/json", OfferingResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/catalog/offerings/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :offering),
         {:ok, offering} <-
           Catalog.update_offering(Helpers.actor(conn), id, Helpers.body(params, "offering")) do
      json(conn, CatalogJSON.offering(offering))
    end
  end

  operation(:archive,
    summary: "Archive an offering",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Offering", "application/json", OfferingResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/catalog/offerings/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :offering),
         {:ok, offering} <- Catalog.archive_offering(Helpers.actor(conn), id) do
      json(conn, CatalogJSON.offering(offering))
    end
  end

  operation(:reorder,
    summary: "Reorder offerings",
    request_body: {"Ordered ids", "application/json", ReorderRequest},
    responses: [
      ok: {"Offerings", "application/json", OfferingListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/catalog/offerings/reorder"
  def reorder(conn, %{"ids" => ids}) do
    with :ok <- Helpers.authorize(conn, :reorder, :offering),
         {:ok, offerings} <- Catalog.reorder_offerings(Helpers.actor(conn), ids) do
      json(conn, CatalogJSON.collection(Enum.map(offerings, &CatalogJSON.offering/1)))
    end
  end

  defp parse_age(filters) do
    case Map.get(filters, "age") do
      nil ->
        filters

      age when is_binary(age) ->
        case Integer.parse(age) do
          {value, ""} -> Map.put(filters, "age", value)
          _ -> Map.delete(filters, "age")
        end

      _ ->
        filters
    end
  end
end
