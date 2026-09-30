defmodule SportsCoachBookingsWeb.Portal.Catalog.PackagesController do
  @moduledoc "Public portal listing of active, visible packages."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookingsWeb.CatalogJSON
  alias SportsCoachBookingsWeb.Schemas.Catalog.PackageListResponse

  tags(["portal"])

  operation(:index,
    summary: "List visible packages",
    responses: [ok: {"Packages", "application/json", PackageListResponse}]
  )

  @doc "GET /api/portal/catalog/packages"
  def index(conn, params) do
    with :ok <- Catalog.Policy.authorize(nil, :list_public, :package) do
      filters = %{"active" => true, "visible_in_portal" => true}
      %{data: data, next_cursor: cursor} = Catalog.page_packages(filters, params)

      offering_ids = Catalog.package_offering_ids(Enum.map(data, & &1.id))

      json(
        conn,
        CatalogJSON.collection(Enum.map(data, &CatalogJSON.package(&1, offering_ids)), cursor)
      )
    end
  end
end
