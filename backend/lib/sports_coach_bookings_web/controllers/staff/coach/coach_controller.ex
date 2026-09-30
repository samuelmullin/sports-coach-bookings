defmodule SportsCoachBookingsWeb.Staff.Coach.CoachController do
  @moduledoc "Staff coach API: own sessions, session roster, player view, bulk attendance."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Feedback
  alias SportsCoachBookings.Feedback.Policy
  alias SportsCoachBookingsWeb.FeedbackJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Feedback, as: S
  alias SportsCoachBookingsWeb.Schemas.Scheduling

  tags(["staff"])

  operation(:index,
    summary: "The coach's assigned sessions",
    parameters: [
      from: [in: :query, type: :string, required: false],
      to: [in: :query, type: :string, required: false]
    ],
    responses: [
      ok: {"Sessions", "application/json", Scheduling.calendar_list_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/coach/sessions"
  def index(conn, params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :list, :feedback) do
      entries = Feedback.list_coach_sessions(actor, Map.take(params, ["from", "to"]))
      json(conn, FeedbackJSON.collection(Enum.map(entries, &FeedbackJSON.session_entry/1)))
    end
  end

  operation(:roster,
    summary: "Session roster with player summaries, attendance, and feedback status",
    parameters: [session_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Roster", "application/json", S.roster_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/coach/sessions/:session_id/roster"
  def roster(conn, %{"session_id" => session_id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :roster, :feedback),
         {:ok, rows} <- Feedback.roster(actor, session_id) do
      json(conn, FeedbackJSON.roster(rows))
    end
  end

  operation(:player,
    summary: "A visible player's profile and recent feedback",
    parameters: [player_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Player", "application/json", S.coach_player_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/coach/players/:player_id"
  def player(conn, %{"player_id" => player_id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :get, :feedback),
         {:ok, result} <- Feedback.coach_player(actor, player_id) do
      json(conn, FeedbackJSON.coach_player(result))
    end
  end

  operation(:attendance,
    summary: "Bulk-mark attendance for a session's bookings",
    parameters: [session_id: [in: :path, type: :string, required: true]],
    request_body: {"Attendance", "application/json", S.attendance_request()},
    responses: [
      ok: {"Attendance", "application/json", S.attendance_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/coach/sessions/:session_id/attendance"
  def attendance(conn, %{"session_id" => session_id} = params) do
    actor = actor(conn)
    entries = attendance_entries(params)

    with :ok <- Policy.authorize(actor, :mark_attendance, :feedback),
         {:ok, results} <- Feedback.mark_attendance(actor, session_id, entries) do
      json(conn, FeedbackJSON.attendance(results))
    end
  end

  defp attendance_entries(params) do
    case params["attendance"] || params["entries"] || [] do
      entries when is_list(entries) -> entries
      _ -> []
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]
end
