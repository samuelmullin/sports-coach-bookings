defmodule SportsCoachBookingsWeb.Staff.Players.PlayersController do
  @moduledoc "Staff read/update API for players (owner/admin, plus coach when visible)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Policy
  alias SportsCoachBookingsWeb.Players.Helpers
  alias SportsCoachBookingsWeb.PlayersJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Players.PlayerListResponse
  alias SportsCoachBookingsWeb.Schemas.Players.PlayerProfileRequest
  alias SportsCoachBookingsWeb.Schemas.Players.PlayerProfileResponse
  alias SportsCoachBookingsWeb.Schemas.Players.PlayerRequest
  alias SportsCoachBookingsWeb.Schemas.Players.PlayerResponse

  tags(["staff"])

  operation(:index,
    summary: "Search players",
    parameters: [
      q: [in: :query, type: :string, required: false],
      include_inactive: [in: :query, type: :boolean, required: false]
    ],
    responses: [
      ok: {"Players", "application/json", PlayerListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/players"
  def index(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :list, :player) do
      %{data: data, next_cursor: cursor} = Players.page_search(Map.get(params, "q"), params)

      json(conn, PlayersJSON.collection(Enum.map(data, &PlayersJSON.player/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a player",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Player", "application/json", PlayerResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/players/:id"
  def show(conn, %{"id" => id}) do
    with {:ok, player} <- Players.fetch_player_detail(id),
         :ok <- Policy.authorize(actor(conn), :get, player) do
      json(conn, PlayersJSON.player_detail(player))
    end
  end

  operation(:update,
    summary: "Update a player",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Player", "application/json", PlayerRequest},
    responses: [
      ok: {"Player", "application/json", PlayerResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/players/:id"
  def update(conn, %{"id" => id} = params) do
    with {:ok, player} <- Players.fetch_player(id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         attrs = params |> Helpers.body("player") |> Map.drop(["household_id"]),
         {:ok, updated} <- Players.update_player(actor(conn), id, attrs) do
      json(conn, PlayersJSON.player(updated))
    end
  end

  operation(:update_profile,
    summary: "Create or update a player's profile",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Profile", "application/json", PlayerProfileRequest},
    responses: [
      ok: {"Profile", "application/json", PlayerProfileResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PUT /api/staff/players/:id/profile"
  def update_profile(conn, %{"id" => id} = params) do
    with {:ok, player} <- Players.fetch_player(id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, profile} <-
           Players.upsert_profile(actor(conn), player, Helpers.body(params, "profile")) do
      json(conn, PlayersJSON.profile(profile))
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]
end
