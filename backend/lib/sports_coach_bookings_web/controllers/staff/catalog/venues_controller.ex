defmodule SportsCoachBookingsWeb.Staff.Catalog.VenuesController do
  @moduledoc "Staff CRUD for venues (owner/admin write, coach read)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookingsWeb.CatalogJSON
  alias SportsCoachBookingsWeb.Schemas.Catalog.{VenueListResponse, VenueRequest, VenueResponse}
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Staff.Catalog.Helpers

  tags(["staff"])

  operation(:index,
    summary: "List venues",
    responses: [
      ok: {"Venues", "application/json", VenueListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/catalog/venues"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :venue) do
      filters = Map.take(params, ["active"])
      %{data: data, next_cursor: cursor} = Catalog.page_venues(filters, params)

      json(conn, CatalogJSON.collection(Enum.map(data, &CatalogJSON.venue/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a venue",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Venue", "application/json", VenueResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/catalog/venues/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :venue),
         {:ok, venue} <- Catalog.fetch_venue(id) do
      json(conn, CatalogJSON.venue(venue))
    end
  end

  operation(:create,
    summary: "Create a venue",
    request_body: {"Venue", "application/json", VenueRequest},
    responses: [
      created: {"Venue", "application/json", VenueResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/catalog/venues"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :venue),
         {:ok, venue} <- Catalog.create_venue(Helpers.actor(conn), Helpers.body(params, "venue")) do
      conn
      |> put_status(:created)
      |> json(CatalogJSON.venue(venue))
    end
  end

  operation(:update,
    summary: "Update a venue",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Venue", "application/json", VenueRequest},
    responses: [
      ok: {"Venue", "application/json", VenueResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/catalog/venues/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :venue),
         {:ok, venue} <-
           Catalog.update_venue(Helpers.actor(conn), id, Helpers.body(params, "venue")) do
      json(conn, CatalogJSON.venue(venue))
    end
  end

  operation(:archive,
    summary: "Archive a venue",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Venue", "application/json", VenueResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/catalog/venues/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :venue),
         {:ok, venue} <- Catalog.archive_venue(Helpers.actor(conn), id) do
      json(conn, CatalogJSON.venue(venue))
    end
  end
end
