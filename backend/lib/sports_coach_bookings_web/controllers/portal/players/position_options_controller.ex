defmodule SportsCoachBookingsWeb.Portal.Players.PositionOptionsController do
  @moduledoc "Portal listing of the tenant's position options."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Policy
  alias SportsCoachBookingsWeb.PlayersJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Players.PositionOptionListResponse

  tags(["portal"])

  operation(:index,
    summary: "List position options",
    responses: [
      ok: {"Position options", "application/json", PositionOptionListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/position_options"
  def index(conn, _params) do
    actor = conn.assigns[:current_customer_actor]

    with :ok <- Policy.authorize(actor, :list_position_options, :position_option) do
      data = Players.list_position_options() |> Enum.map(&PlayersJSON.position_option/1)
      json(conn, PlayersJSON.collection(data))
    end
  end
end
