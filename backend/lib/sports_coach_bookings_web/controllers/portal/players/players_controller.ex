defmodule SportsCoachBookingsWeb.Portal.Players.PlayersController do
  @moduledoc "Portal CRUD for a household's players and their profiles."

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

  tags(["portal"])

  operation(:index,
    summary: "List the household's players",
    responses: [
      ok: {"Players", "application/json", PlayerListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/players"
  def index(conn, params) do
    actor = conn.assigns[:current_customer_actor]

    with :ok <- Policy.authorize(actor, :list, :player) do
      %{data: data, next_cursor: cursor} =
        Players.page_for_household(actor.household_id, params, preload: [:emergency_contacts])

      json(
        conn,
        PlayersJSON.collection(Enum.map(data, &PlayersJSON.player_with_contacts/1), cursor)
      )
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

  @doc "GET /api/portal/players/:id"
  def show(conn, %{"id" => id}) do
    with {:ok, player} <- Players.fetch_player_detail(id),
         :ok <- Policy.authorize(actor(conn), :get, player) do
      json(conn, PlayersJSON.player_detail(player))
    end
  end

  operation(:create,
    summary: "Create a player",
    request_body: {"Player", "application/json", PlayerRequest},
    responses: [
      created: {"Player", "application/json", PlayerResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/players"
  def create(conn, params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :create, :player) do
      attrs =
        params
        |> Helpers.body("player")
        |> Map.put("household_id", actor.household_id)

      case Players.create_player(actor, attrs) do
        {:ok, player} ->
          conn
          |> put_status(:created)
          |> json(PlayersJSON.player(player))

        {:error, changeset} ->
          {:error, changeset}
      end
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

  @doc "PATCH /api/portal/players/:id"
  def update(conn, %{"id" => id} = params) do
    with {:ok, player} <- Players.fetch_player(id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         attrs = params |> Helpers.body("player") |> Map.drop(["household_id"]),
         {:ok, updated} <- Players.update_player(actor(conn), id, attrs) do
      json(conn, PlayersJSON.player(updated))
    end
  end

  operation(:archive,
    summary: "Archive a player",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Player", "application/json", PlayerResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/players/:id/archive"
  def archive(conn, %{"id" => id}) do
    with {:ok, player} <- Players.fetch_player(id),
         :ok <- Policy.authorize(actor(conn), :archive, player),
         {:ok, archived} <- Players.archive_player(actor(conn), id) do
      json(conn, PlayersJSON.player(archived))
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

  @doc "PUT /api/portal/players/:id/profile"
  def update_profile(conn, %{"id" => id} = params) do
    with {:ok, player} <- Players.fetch_player(id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, profile} <-
           Players.upsert_profile(actor(conn), player, Helpers.body(params, "profile")) do
      json(conn, PlayersJSON.profile(profile))
    end
  end

  defp actor(conn), do: conn.assigns[:current_customer_actor]
end
