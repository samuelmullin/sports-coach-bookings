defmodule SportsCoachBookingsWeb.Staff.Players.MedicalController do
  @moduledoc "Staff medical endpoint. Every read is audited."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Policy
  alias SportsCoachBookingsWeb.Players.Helpers
  alias SportsCoachBookingsWeb.PlayersJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Players.MedicalInfoRequest
  alias SportsCoachBookingsWeb.Schemas.Players.MedicalInfoResponse

  tags(["staff"])

  operation(:show,
    summary: "Read a player's medical info (audited)",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Medical info", "application/json", MedicalInfoResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/players/:id/medical"
  def show(conn, %{"id" => id}) do
    with {:ok, player} <- Players.fetch_player(id),
         :ok <- Policy.authorize(actor(conn), :read_medical, player),
         {:ok, medical} <- Players.read_medical_info(actor(conn), player) do
      json(conn, serialize(medical, player))
    end
  end

  operation(:update,
    summary: "Create or update a player's medical info (audited)",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Medical info", "application/json", MedicalInfoRequest},
    responses: [
      ok: {"Medical info", "application/json", MedicalInfoResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PUT /api/staff/players/:id/medical"
  def update(conn, %{"id" => id} = params) do
    with {:ok, player} <- Players.fetch_player(id),
         :ok <- Policy.authorize(actor(conn), :update_medical, player),
         {:ok, medical} <-
           Players.upsert_medical_info(actor(conn), player, Helpers.body(params, "medical_info")) do
      json(conn, PlayersJSON.medical_info(medical))
    end
  end

  defp serialize(nil, player) do
    %{
      player_id: player.id,
      allergies: nil,
      conditions: nil,
      medications: nil,
      notes: nil,
      has_medical_info: false,
      updated_at: nil
    }
  end

  defp serialize(medical, _player), do: PlayersJSON.medical_info(medical)

  defp actor(conn), do: conn.assigns[:current_staff_actor]
end
