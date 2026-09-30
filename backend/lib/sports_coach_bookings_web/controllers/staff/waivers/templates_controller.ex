defmodule SportsCoachBookingsWeb.Staff.Waivers.TemplatesController do
  @moduledoc "Staff CRUD for waiver templates."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Waivers
  alias SportsCoachBookingsWeb.Waivers.Helpers
  alias SportsCoachBookingsWeb.WaiversJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  alias SportsCoachBookingsWeb.Schemas.Waivers.{
    WaiverTemplateListResponse,
    WaiverTemplateRequest,
    WaiverTemplateResponse
  }

  tags(["staff"])

  operation(:index,
    summary: "List waiver templates",
    parameters: [
      active: [in: :query, type: :boolean, required: false],
      scope: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [ok: {"Waiver templates", "application/json", WaiverTemplateListResponse}]
  )

  @doc "GET /api/staff/waivers/templates"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :waiver_template) do
      filters = Map.take(params, ["active", "scope"])
      %{data: data, next_cursor: cursor} = Waivers.page_templates(filters, params)

      json(conn, WaiversJSON.collection(Enum.map(data, &serialize/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a waiver template",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Waiver template", "application/json", WaiverTemplateResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/waivers/templates/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :waiver_template),
         {:ok, template} <- Waivers.fetch_template(id) do
      json(conn, serialize(template))
    end
  end

  operation(:create,
    summary: "Create a waiver template",
    request_body: {"Waiver template", "application/json", WaiverTemplateRequest},
    responses: [
      created: {"Waiver template", "application/json", WaiverTemplateResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/waivers/templates"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :waiver_template),
         {:ok, template} <-
           Waivers.create_template(Helpers.actor(conn), Helpers.body(params, "template")) do
      conn |> put_status(:created) |> json(serialize(template))
    end
  end

  operation(:update,
    summary: "Update a waiver template",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Waiver template", "application/json", WaiverTemplateRequest},
    responses: [
      ok: {"Waiver template", "application/json", WaiverTemplateResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/waivers/templates/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :waiver_template),
         {:ok, template} <-
           Waivers.update_template(Helpers.actor(conn), id, Helpers.body(params, "template")) do
      json(conn, serialize(template))
    end
  end

  operation(:archive,
    summary: "Archive a waiver template",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Waiver template", "application/json", WaiverTemplateResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/waivers/templates/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :waiver_template),
         {:ok, template} <- Waivers.archive_template(Helpers.actor(conn), id) do
      json(conn, serialize(template))
    end
  end

  defp serialize(template) do
    WaiversJSON.template(template, Waivers.template_offering_ids(template.id))
  end
end
