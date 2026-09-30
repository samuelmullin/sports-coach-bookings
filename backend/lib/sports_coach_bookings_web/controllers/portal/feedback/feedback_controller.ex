defmodule SportsCoachBookingsWeb.Portal.Feedback.FeedbackController do
  @moduledoc "Portal: a household's player feedback (shared rows only)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Feedback
  alias SportsCoachBookings.Feedback.Policy
  alias SportsCoachBookings.Players
  alias SportsCoachBookingsWeb.FeedbackJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Feedback, as: S

  tags(["portal"])

  operation(:index,
    summary: "Shared feedback for a household player, newest first",
    parameters: [player_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Feedback", "application/json", S.feedback_list()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/players/:player_id/feedback"
  def index(conn, %{"player_id" => player_id}) do
    actor = conn.assigns[:current_customer_actor]

    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Policy.authorize(actor, :list_shared, player) do
      rows = Feedback.shared_for_player(player_id)
      json(conn, FeedbackJSON.collection(Enum.map(rows, &FeedbackJSON.feedback/1)))
    end
  end
end
