defmodule SportsCoachBookingsWeb.Staff.Players.PositionOptionsController do
  @moduledoc "Staff management of the tenant's position options."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Policy
  alias SportsCoachBookingsWeb.Players.Helpers
  alias SportsCoachBookingsWeb.PlayersJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Players.PositionOptionListResponse
  alias SportsCoachBookingsWeb.Schemas.Players.PositionOptionResponse

  tags(["staff"])

  operation(:index,
    summary: "List position options",
    responses: [
      ok: {"Position options", "application/json", PositionOptionListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/position_options"
  def index(conn, _params) do
    with :ok <- Policy.authorize(actor(conn), :list_position_options, :position_option) do
      data = Players.list_position_options() |> Enum.map(&PlayersJSON.position_option/1)
      json(conn, PlayersJSON.collection(data))
    end
  end

  operation(:create,
    summary: "Create a position option",
    responses: [
      created: {"Position option", "application/json", PositionOptionResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/position_options"
  def create(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :manage_position_options, :position_option),
         {:ok, option} <-
           Players.create_position_option(actor(conn), Helpers.body(params, "position_option")) do
      conn
      |> put_status(:created)
      |> json(PlayersJSON.position_option(option))
    end
  end

  operation(:update,
    summary: "Update a position option",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Position option", "application/json", PositionOptionResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/position_options/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Policy.authorize(actor(conn), :manage_position_options, :position_option),
         {:ok, option} <-
           Players.update_position_option(
             actor(conn),
             id,
             Helpers.body(params, "position_option")
           ) do
      json(conn, PlayersJSON.position_option(option))
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]
end
