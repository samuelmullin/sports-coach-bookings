defmodule SportsCoachBookingsWeb.Staff.Bookings.BookingsController do
  @moduledoc "Staff: book on behalf, history, session roster, cancel/override, attendance."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Bookings.Policy
  alias SportsCoachBookingsWeb.BookingsJSON
  alias SportsCoachBookingsWeb.Schemas.Bookings, as: S
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["staff"])

  operation(:index,
    summary: "Booking history",
    parameters: [
      status: [in: :query, type: :string, required: false],
      household_id: [in: :query, type: :string, required: false],
      player_id: [in: :query, type: :string, required: false],
      session_id: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Bookings", "application/json", S.booking_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/bookings"
  def index(conn, params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :history, :booking) do
      filters = Map.take(params, ["status", "household_id", "player_id", "session_id"])
      %{data: data, next_cursor: cursor} = Bookings.page_bookings(filters, params)
      json(conn, BookingsJSON.collection(Enum.map(data, &BookingsJSON.entry/1), cursor))
    end
  end

  operation(:show,
    summary: "Booking detail with history",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Booking", "application/json", S.history_response()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/bookings/:id"
  def show(conn, %{"id" => id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :history, :booking),
         {:ok, booking} <- Bookings.fetch_booking(id) do
      events = Bookings.list_booking_events(id)

      json(conn, %{
        booking: BookingsJSON.booking(booking),
        events: Enum.map(events, &BookingsJSON.event/1)
      })
    end
  end

  operation(:create,
    summary: "Book a player on behalf of a household",
    request_body: {"Booking", "application/json", S.create_request()},
    responses: [
      created: {"Booking", "application/json", S.booking()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Not bookable", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/bookings"
  def create(conn, params) do
    actor = actor(conn)
    attrs = Map.get(params, "booking", params)

    with :ok <- Policy.authorize(actor, :book_on_behalf, :booking),
         {:ok, booking} <-
           Bookings.book(actor, attrs["player_id"], attrs["session_id"],
             method: attrs["method"] || "comp",
             override: attrs["override"] == true,
             reason: attrs["reason"]
           ) do
      conn |> put_status(:created) |> json(BookingsJSON.booking(booking))
    end
  end

  operation(:roster,
    summary: "Session roster",
    parameters: [session_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Roster", "application/json", S.roster_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/sessions/:session_id/roster"
  def roster(conn, %{"session_id" => session_id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :roster, :session) do
      json(conn, BookingsJSON.roster(Bookings.session_roster(session_id)))
    end
  end

  operation(:cancel,
    summary: "Cancel a booking (staff override supported)",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Cancel", "application/json", S.cancel_request()},
    responses: [
      ok: {"Booking", "application/json", S.booking()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/bookings/:id/cancel"
  def cancel(conn, %{"id" => id} = params) do
    actor = actor(conn)
    attrs = Map.get(params, "cancel", params)

    with :ok <- Policy.authorize(actor, :override_cancel, :booking),
         {:ok, booking} <-
           Bookings.cancel(actor, id,
             reason: attrs["reason"],
             outcome: outcome_atom(attrs["outcome"]),
             refund_pct: attrs["refund_pct"]
           ) do
      json(conn, BookingsJSON.booking(booking))
    end
  end

  operation(:attendance,
    summary: "Mark a booking attended or no-show",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Attendance", "application/json", S.attendance_request()},
    responses: [
      ok: {"Booking", "application/json", S.booking()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Not allowed", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/bookings/:id/attendance"
  def attendance(conn, %{"id" => id} = params) do
    actor = actor(conn)
    attrs = Map.get(params, "attendance", params)

    with :ok <- Policy.authorize(actor, :mark_attendance, :booking),
         {:ok, booking} <- Bookings.mark_attendance(actor, id, status_atom(attrs["status"])) do
      json(conn, BookingsJSON.booking(booking))
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp status_atom("attended"), do: :attended
  defp status_atom("no_show"), do: :no_show
  defp status_atom(_), do: :invalid

  defp outcome_atom("full_return"), do: :full_return
  defp outcome_atom("forfeit"), do: :forfeit
  defp outcome_atom("credit_return"), do: :credit_return
  defp outcome_atom("provider_cancelled"), do: :provider_cancelled
  defp outcome_atom("partial_refund"), do: :partial_refund
  defp outcome_atom(_), do: nil
end
