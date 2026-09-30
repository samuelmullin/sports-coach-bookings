defmodule SportsCoachBookingsWeb.Staff.Schedule.SessionsController do
  @moduledoc "Staff scheduling: calendar, session CRUD, series, cancel, reschedule."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookingsWeb.SchedulingJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Scheduling, as: S
  alias SportsCoachBookingsWeb.Staff.Schedule.Helpers

  tags(["staff"])

  operation(:index,
    summary: "Staff calendar of sessions",
    parameters: [
      from: [in: :query, type: :string, required: false],
      to: [in: :query, type: :string, required: false],
      venue_id: [in: :query, type: :string, required: false],
      offering_id: [in: :query, type: :string, required: false],
      coach_id: [in: :query, type: :string, required: false],
      status: [in: :query, type: :string, required: false]
    ],
    responses: [
      ok: {"Calendar", "application/json", S.calendar_list_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/schedule/sessions"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :calendar) do
      filters = Map.take(params, ["from", "to", "venue_id", "offering_id", "coach_id", "status"])
      entries = Scheduling.calendar(filters, include_hidden: true)

      json(conn, SchedulingJSON.collection(Enum.map(entries, &SchedulingJSON.calendar_entry/1)))
    end
  end

  operation(:show,
    summary: "Session detail with roster",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Session detail", "application/json", S.session_detail()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/schedule/sessions/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :session),
         {:ok, entry} <- Scheduling.session_detail(id) do
      json(conn, SchedulingJSON.calendar_entry(entry))
    end
  end

  operation(:create,
    summary: "Create a single session",
    request_body: {"Session", "application/json", S.session_request()},
    responses: [
      created: {"Session", "application/json", S.session_create_response()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/schedule/sessions"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :session),
         {:ok, result} <-
           translate(
             Scheduling.create_session(Helpers.actor(conn), Helpers.body(params, "session"))
           ) do
      conn |> put_status(:created) |> json(session_result(result))
    end
  end

  operation(:create_series,
    summary: "Create a session series",
    request_body: {"Series", "application/json", S.series_request()},
    responses: [
      created: {"Series", "application/json", S.series_create_response()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/schedule/series"
  def create_series(conn, params) do
    with :ok <- Helpers.authorize(conn, :create_series, :session_series),
         {:ok, %{series: series, sessions: sessions, warnings: warnings}} <-
           translate(
             Scheduling.create_series(Helpers.actor(conn), Helpers.body(params, "series"))
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        series: SchedulingJSON.series(series),
        sessions: Enum.map(sessions, &SchedulingJSON.session/1),
        warnings: Enum.map(warnings, &SchedulingJSON.warning/1)
      })
    end
  end

  operation(:update,
    summary: "Update a session",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Session", "application/json", S.session_request()},
    responses: [
      ok: {"Session", "application/json", S.session_edit_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/schedule/sessions/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :session),
         {:ok, result} <-
           translate(
             Scheduling.update_session(Helpers.actor(conn), id, Helpers.body(params, "session"))
           ) do
      json(conn, session_result(result))
    end
  end

  operation(:reschedule,
    summary: "Reschedule a session",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Reschedule", "application/json", S.reschedule_request()},
    responses: [
      ok: {"Session", "application/json", S.session_edit_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/schedule/sessions/:id/reschedule"
  def reschedule(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :reschedule, :session),
         {:ok, result} <-
           translate(
             Scheduling.reschedule_session(
               Helpers.actor(conn),
               id,
               Helpers.body(params, "session")
             )
           ) do
      json(conn, session_result(result))
    end
  end

  operation(:cancel,
    summary: "Cancel a session",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Cancel", "application/json", S.cancel_request()},
    responses: [
      ok: {"Session", "application/json", S.cancel_response()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/schedule/sessions/:id/cancel"
  def cancel(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :cancel, :session),
         {:ok, result} <- Scheduling.cancel_session(Helpers.actor(conn), id, params["reason"]) do
      json(conn, SchedulingJSON.cancelled(result))
    end
  end

  operation(:edit_series,
    summary: "Edit a session series (single / following / all)",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Series edit", "application/json", S.series_edit_request()},
    responses: [
      ok: {"Sessions", "application/json", S.series_edit_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/schedule/sessions/:id/edit_series"
  def edit_series(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :edit_series, :session_series),
         {:ok, target_id} <- series_target_id(id, params["scope"]),
         {:ok, %{sessions: sessions, series: series, warnings: warnings}} <-
           translate(
             Scheduling.update_series(
               Helpers.actor(conn),
               scope_atom(params["scope"]),
               target_id,
               Map.drop(params, ["id"]),
               confirm: params["confirm"] == true or params["confirm"] == "true"
             )
           ) do
      json(conn, %{
        series: if(series, do: SchedulingJSON.series(series)),
        sessions: Enum.map(sessions, &SchedulingJSON.session/1),
        warnings: Enum.map(warnings, &SchedulingJSON.warning/1)
      })
    end
  end

  operation(:my_sessions,
    summary: "The acting coach's sessions",
    parameters: [
      from: [in: :query, type: :string, required: false],
      to: [in: :query, type: :string, required: false]
    ],
    responses: [
      ok: {"Calendar", "application/json", S.calendar_list_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/my-sessions"
  def my_sessions(conn, params) do
    with :ok <- Helpers.authorize(conn, :my_sessions, :calendar),
         membership_id when is_binary(membership_id) <- Helpers.membership_id(conn) do
      filters = Map.take(params, ["from", "to"])
      entries = Scheduling.my_sessions(membership_id, filters)

      json(conn, SchedulingJSON.collection(Enum.map(entries, &SchedulingJSON.calendar_entry/1)))
    else
      _ -> {:error, :forbidden}
    end
  end

  defp session_result(%{session: session, warnings: warnings}) do
    %{
      session: SchedulingJSON.session(session),
      warnings: Enum.map(warnings, &SchedulingJSON.warning/1)
    }
  end

  defp series_target_id(id, "all") do
    case Scheduling.fetch_session(id) do
      {:ok, session} -> {:ok, session.series_id || session.id}
      {:error, :not_found} -> {:ok, id}
    end
  end

  defp series_target_id(id, _), do: {:ok, id}

  defp scope_atom("all"), do: :all
  defp scope_atom("following"), do: :following
  defp scope_atom(_), do: :single

  defp translate({:error, {:capacity_below_bookings, count}}) do
    {:error,
     {:capacity_below_bookings, "capacity is below the #{count} confirmed + held bookings"}}
  end

  defp translate({:error, {:bookings_exist, count}}) do
    {:error,
     {:bookings_exist, "#{count} targeted session(s) already have bookings; pass confirm=true"}}
  end

  defp translate({:error, {:invalid_coach, id}}) do
    {:error, {:invalid_coach, "no active coach membership #{id}"}}
  end

  defp translate(other), do: other
end
