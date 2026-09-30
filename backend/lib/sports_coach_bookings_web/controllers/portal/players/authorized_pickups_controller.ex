defmodule SportsCoachBookingsWeb.Portal.Players.AuthorizedPickupsController do
  @moduledoc "Portal CRUD for a player's authorized pickups."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Policy
  alias SportsCoachBookingsWeb.Players.Helpers
  alias SportsCoachBookingsWeb.PlayersJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Players.AuthorizedPickupListResponse
  alias SportsCoachBookingsWeb.Schemas.Players.AuthorizedPickupRequest
  alias SportsCoachBookingsWeb.Schemas.Players.AuthorizedPickupResponse

  tags(["portal"])

  operation(:index,
    summary: "List a player's authorized pickups",
    parameters: [player_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Pickups", "application/json", AuthorizedPickupListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/players/:player_id/authorized_pickups"
  def index(conn, %{"player_id" => player_id}) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :get, player) do
      data =
        Players.list_authorized_pickups(player.id) |> Enum.map(&PlayersJSON.authorized_pickup/1)

      json(conn, PlayersJSON.collection(data))
    end
  end

  operation(:create,
    summary: "Add an authorized pickup",
    parameters: [player_id: [in: :path, type: :string, required: true]],
    request_body: {"Pickup", "application/json", AuthorizedPickupRequest},
    responses: [
      created: {"Pickup", "application/json", AuthorizedPickupResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/players/:player_id/authorized_pickups"
  def create(conn, %{"player_id" => player_id} = params) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, pickup} <-
           Players.create_authorized_pickup(player, Helpers.body(params, "authorized_pickup")) do
      conn
      |> put_status(:created)
      |> json(PlayersJSON.authorized_pickup(pickup))
    end
  end

  operation(:update,
    summary: "Update an authorized pickup",
    parameters: [
      player_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    request_body: {"Pickup", "application/json", AuthorizedPickupRequest},
    responses: [
      ok: {"Pickup", "application/json", AuthorizedPickupResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/portal/players/:player_id/authorized_pickups/:id"
  def update(conn, %{"player_id" => player_id, "id" => id} = params) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, pickup} <-
           Players.update_authorized_pickup(
             player,
             id,
             Helpers.body(params, "authorized_pickup")
           ) do
      json(conn, PlayersJSON.authorized_pickup(pickup))
    end
  end

  operation(:delete,
    summary: "Delete an authorized pickup",
    parameters: [
      player_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    responses: [
      no_content: "Deleted",
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/portal/players/:player_id/authorized_pickups/:id"
  def delete(conn, %{"player_id" => player_id, "id" => id}) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, _pickup} <- Players.delete_authorized_pickup(player, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp actor(conn), do: conn.assigns[:current_customer_actor]
end
