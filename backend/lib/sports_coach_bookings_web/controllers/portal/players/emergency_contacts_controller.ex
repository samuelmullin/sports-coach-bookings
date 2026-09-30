defmodule SportsCoachBookingsWeb.Portal.Players.EmergencyContactsController do
  @moduledoc "Portal CRUD for a player's emergency contacts."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Policy
  alias SportsCoachBookingsWeb.Players.Helpers
  alias SportsCoachBookingsWeb.PlayersJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Players.EmergencyContactListResponse
  alias SportsCoachBookingsWeb.Schemas.Players.EmergencyContactRequest
  alias SportsCoachBookingsWeb.Schemas.Players.EmergencyContactResponse

  tags(["portal"])

  operation(:index,
    summary: "List a player's emergency contacts",
    parameters: [player_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Contacts", "application/json", EmergencyContactListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/players/:player_id/emergency_contacts"
  def index(conn, %{"player_id" => player_id}) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :get, player) do
      data =
        Players.list_emergency_contacts(player.id) |> Enum.map(&PlayersJSON.emergency_contact/1)

      json(conn, PlayersJSON.collection(data))
    end
  end

  operation(:create,
    summary: "Add an emergency contact",
    parameters: [player_id: [in: :path, type: :string, required: true]],
    request_body: {"Contact", "application/json", EmergencyContactRequest},
    responses: [
      created: {"Contact", "application/json", EmergencyContactResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/players/:player_id/emergency_contacts"
  def create(conn, %{"player_id" => player_id} = params) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, contact} <-
           Players.create_emergency_contact(player, Helpers.body(params, "emergency_contact")) do
      conn
      |> put_status(:created)
      |> json(PlayersJSON.emergency_contact(contact))
    end
  end

  operation(:update,
    summary: "Update an emergency contact",
    parameters: [
      player_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    request_body: {"Contact", "application/json", EmergencyContactRequest},
    responses: [
      ok: {"Contact", "application/json", EmergencyContactResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/portal/players/:player_id/emergency_contacts/:id"
  def update(conn, %{"player_id" => player_id, "id" => id} = params) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, contact} <-
           Players.update_emergency_contact(
             player,
             id,
             Helpers.body(params, "emergency_contact")
           ) do
      json(conn, PlayersJSON.emergency_contact(contact))
    end
  end

  operation(:delete,
    summary: "Delete an emergency contact",
    parameters: [
      player_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    responses: [
      no_content: "Deleted",
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/portal/players/:player_id/emergency_contacts/:id"
  def delete(conn, %{"player_id" => player_id, "id" => id}) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor(conn), :update, player),
         {:ok, _contact} <- Players.delete_emergency_contact(player, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp actor(conn), do: conn.assigns[:current_customer_actor]
end
