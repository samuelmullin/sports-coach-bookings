defmodule SportsCoachBookingsWeb.Portal.Catalog.OfferingsController do
  @moduledoc "Public portal listing of active offerings."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookingsWeb.CatalogJSON

  alias SportsCoachBookingsWeb.Schemas.Catalog.{
    OfferingListResponse,
    PackageListResponse
  }

  tags(["portal"])

  operation(:index,
    summary: "List active offerings",
    parameters: [
      format: [in: :query, type: :string, required: false],
      age: [in: :query, type: :integer, required: false]
    ],
    responses: [ok: {"Offerings", "application/json", OfferingListResponse}]
  )

  @doc "GET /api/portal/catalog/offerings"
  def index(conn, params) do
    with :ok <- Catalog.Policy.authorize(nil, :list_public, :offering) do
      filters = params |> Map.take(["format", "age"]) |> Map.put("active", true)
      %{data: data, next_cursor: cursor} = Catalog.page_offerings(filters, params)

      json(conn, CatalogJSON.collection(Enum.map(data, &CatalogJSON.offering/1), cursor))
    end
  end

  operation(:packages,
    summary: "List packages available for an offering",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Packages", "application/json", PackageListResponse}]
  )

  @doc "GET /api/portal/catalog/offerings/:id/packages"
  def packages(conn, %{"id" => id}) do
    with :ok <- Catalog.Policy.authorize(nil, :list_public, :package) do
      data = Catalog.list_packages_for_offering(id)
      offering_ids = Catalog.package_offering_ids(Enum.map(data, & &1.id))

      json(conn, CatalogJSON.collection(Enum.map(data, &CatalogJSON.package(&1, offering_ids))))
    end
  end
end
