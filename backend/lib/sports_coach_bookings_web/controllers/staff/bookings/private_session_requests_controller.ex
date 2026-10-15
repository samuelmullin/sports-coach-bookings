defmodule SportsCoachBookingsWeb.Staff.Bookings.PrivateSessionRequestsController do
  @moduledoc "Staff review queue for customer-requested private sessions."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias OpenApiSpex.Schema
  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Bookings.Policy
  alias SportsCoachBookingsWeb.BookingsJSON
  alias SportsCoachBookingsWeb.Schemas.Bookings, as: BookingSchemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["staff"])

  operation(:index,
    summary: "List private-session requests",
    parameters: [
      status: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok:
        {"Requests", "application/json",
         BookingSchemas.list(BookingSchemas.private_session_request_response())},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  def index(conn, params) do
    actor = conn.assigns[:current_staff_actor]

    with :ok <- Policy.authorize(actor, :list_private_requests, :session) do
      result = Bookings.page_private_session_requests(Map.take(params, ["status"]), params)

      json(conn, %{
        data: Enum.map(result.data, &BookingsJSON.private_session_request/1),
        next_cursor: result.next_cursor
      })
    end
  end

  operation(:update,
    summary: "Approve or decline a private-session request",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body:
      {"Review", "application/json",
       %Schema{
         type: :object,
         properties: %{
           status: %Schema{type: :string, enum: ["approved", "declined"]},
           session_id: %Schema{type: :string, format: :uuid, nullable: true},
           decline_reason: %Schema{type: :string, nullable: true}
         },
         required: [:status]
       }},
    responses: [
      ok: {"Request", "application/json", BookingSchemas.private_session_request_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    actor = conn.assigns[:current_staff_actor]
    attrs = Map.get(params, "review", params)

    with :ok <- Policy.authorize(actor, :review_private_request, :session),
         {:ok, request} <-
           Bookings.review_private_session_request(actor, id, attrs["status"], attrs) do
      json(conn, BookingsJSON.private_session_request(request))
    end
  end
end
