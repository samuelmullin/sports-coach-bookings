defmodule SportsCoachBookingsWeb.Staff.Catalog.PackagesController do
  @moduledoc "Staff CRUD, reordering, and offering assignment for packages."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookingsWeb.CatalogJSON

  alias SportsCoachBookingsWeb.Schemas.Catalog.{
    PackageListResponse,
    PackageRequest,
    PackageResponse,
    ReorderRequest
  }

  alias SportsCoachBookingsWeb.Staff.Catalog.Helpers

  tags(["staff"])

  operation(:index,
    summary: "List packages",
    parameters: [
      active: [in: :query, type: :boolean, required: false],
      visible_in_portal: [in: :query, type: :boolean, required: false]
    ],
    responses: [ok: {"Packages", "application/json", PackageListResponse}]
  )

  @doc "GET /api/staff/catalog/packages"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :package) do
      filters = Map.take(params, ["active", "visible_in_portal"])
      %{data: data, next_cursor: cursor} = Catalog.page_packages(filters, params)

      offering_ids = Catalog.package_offering_ids(Enum.map(data, & &1.id))

      json(
        conn,
        CatalogJSON.collection(Enum.map(data, &CatalogJSON.package(&1, offering_ids)), cursor)
      )
    end
  end

  operation(:show,
    summary: "Get a package",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Package", "application/json", PackageResponse}]
  )

  @doc "GET /api/staff/catalog/packages/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :package),
         {:ok, package} <- Catalog.fetch_package(id) do
      json(conn, CatalogJSON.package(package))
    end
  end

  operation(:create,
    summary: "Create a package",
    request_body: {"Package", "application/json", PackageRequest},
    responses: [created: {"Package", "application/json", PackageResponse}]
  )

  @doc "POST /api/staff/catalog/packages"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :package),
         {:ok, package} <-
           Catalog.create_package(Helpers.actor(conn), Helpers.body(params, "package")) do
      conn
      |> put_status(:created)
      |> json(CatalogJSON.package(package))
    end
  end

  operation(:update,
    summary: "Update a package",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Package", "application/json", PackageRequest},
    responses: [ok: {"Package", "application/json", PackageResponse}]
  )

  @doc "PATCH /api/staff/catalog/packages/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :package),
         {:ok, package} <-
           Catalog.update_package(Helpers.actor(conn), id, Helpers.body(params, "package")) do
      json(conn, CatalogJSON.package(package))
    end
  end

  operation(:archive,
    summary: "Archive a package",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Package", "application/json", PackageResponse}]
  )

  @doc "POST /api/staff/catalog/packages/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :package),
         {:ok, package} <- Catalog.archive_package(Helpers.actor(conn), id) do
      json(conn, CatalogJSON.package(package))
    end
  end

  operation(:reorder,
    summary: "Reorder packages",
    request_body: {"Ordered ids", "application/json", ReorderRequest},
    responses: [ok: {"Packages", "application/json", PackageListResponse}]
  )

  @doc "POST /api/staff/catalog/packages/reorder"
  def reorder(conn, %{"ids" => ids}) do
    with :ok <- Helpers.authorize(conn, :reorder, :package),
         {:ok, packages} <- Catalog.reorder_packages(Helpers.actor(conn), ids) do
      offering_ids = Catalog.package_offering_ids(Enum.map(packages, & &1.id))

      json(
        conn,
        CatalogJSON.collection(Enum.map(packages, &CatalogJSON.package(&1, offering_ids)))
      )
    end
  end

  operation(:set_offerings,
    summary: "Set a package's eligible offerings",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Offering ids", "application/json", ReorderRequest},
    responses: [ok: {"Package", "application/json", PackageResponse}]
  )

  @doc "PUT /api/staff/catalog/packages/:id/offerings"
  def set_offerings(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :package),
         {:ok, package} <-
           Catalog.set_package_offerings(Helpers.actor(conn), id, params["offering_ids"] || []) do
      json(conn, CatalogJSON.package(package))
    end
  end
end
