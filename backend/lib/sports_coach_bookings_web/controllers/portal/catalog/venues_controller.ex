defmodule SportsCoachBookingsWeb.Portal.Catalog.VenuesController do
  @moduledoc "Public portal listing of active venues."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookingsWeb.CatalogJSON
  alias SportsCoachBookingsWeb.Schemas.Catalog.VenueListResponse

  tags(["portal"])

  operation(:index,
    summary: "List active venues",
    responses: [ok: {"Venues", "application/json", VenueListResponse}]
  )

  @doc "GET /api/portal/catalog/venues"
  def index(conn, params) do
    with :ok <- Catalog.Policy.authorize(nil, :list_public, :venue) do
      %{data: data, next_cursor: cursor} = Catalog.page_venues(%{"active" => true}, params)

      json(conn, CatalogJSON.collection(Enum.map(data, &CatalogJSON.venue/1), cursor))
    end
  end
end
