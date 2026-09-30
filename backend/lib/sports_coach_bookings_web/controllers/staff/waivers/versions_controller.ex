defmodule SportsCoachBookingsWeb.Staff.Waivers.VersionsController do
  @moduledoc "Staff drafting and publishing of waiver versions."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Waivers
  alias SportsCoachBookingsWeb.Waivers.Helpers
  alias SportsCoachBookingsWeb.WaiversJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  alias SportsCoachBookingsWeb.Schemas.Waivers.{
    WaiverVersionListResponse,
    WaiverVersionRequest,
    WaiverVersionResponse
  }

  tags(["staff"])

  operation(:index,
    summary: "List a template's versions",
    parameters: [template_id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Waiver versions", "application/json", WaiverVersionListResponse}]
  )

  @doc "GET /api/staff/waivers/templates/:template_id/versions"
  def index(conn, %{"template_id" => template_id}) do
    with :ok <- Helpers.authorize(conn, :list, :waiver_version) do
      versions = Waivers.list_versions(template_id)
      json(conn, WaiversJSON.collection(Enum.map(versions, &WaiversJSON.version/1)))
    end
  end

  operation(:create,
    summary: "Create a draft version",
    parameters: [template_id: [in: :path, type: :string, required: true]],
    request_body: {"Waiver version", "application/json", WaiverVersionRequest},
    responses: [
      created: {"Waiver version", "application/json", WaiverVersionResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/waivers/templates/:template_id/versions"
  def create(conn, %{"template_id" => template_id} = params) do
    with :ok <- Helpers.authorize(conn, :create, :waiver_version),
         {:ok, version} <-
           Waivers.create_version(
             Helpers.actor(conn),
             template_id,
             Helpers.body(params, "version")
           ) do
      conn |> put_status(:created) |> json(WaiversJSON.version(version))
    end
  end

  operation(:update,
    summary: "Update a draft version's body",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Waiver version", "application/json", WaiverVersionRequest},
    responses: [
      ok: {"Waiver version", "application/json", WaiverVersionResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Immutable or validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/waivers/versions/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :waiver_version),
         {:ok, version} <-
           Waivers.update_version(Helpers.actor(conn), id, Helpers.body(params, "version")) do
      json(conn, WaiversJSON.version(version))
    end
  end

  operation(:publish,
    summary: "Publish a draft version",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Waiver version", "application/json", WaiverVersionResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/waivers/versions/:id/publish"
  def publish(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :publish, :waiver_version),
         {:ok, version} <- Waivers.publish_version(Helpers.actor(conn), id) do
      json(conn, WaiversJSON.version(version))
    end
  end

  operation(:preview,
    summary: "Preview a version body",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Waiver version", "application/json", WaiverVersionResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/waivers/versions/:id/preview"
  def preview(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :preview, :waiver_version),
         {:ok, version} <- Waivers.preview_version(id) do
      json(conn, WaiversJSON.version(version))
    end
  end
end
