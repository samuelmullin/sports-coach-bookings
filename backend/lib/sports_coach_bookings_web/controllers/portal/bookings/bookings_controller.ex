defmodule SportsCoachBookingsWeb.Portal.Bookings.BookingsController do
  @moduledoc "Portal: book, list, cancel (with preview), and rebook household bookings."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Bookings.Policy
  alias SportsCoachBookingsWeb.BookingsJSON
  alias SportsCoachBookingsWeb.Schemas.Bookings, as: S
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:index,
    summary: "List the household's bookings",
    parameters: [
      scope: [in: :query, type: :string, required: false, description: "upcoming | past | all"]
    ],
    responses: [
      ok: {"Bookings", "application/json", S.booking_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/bookings"
  def index(conn, params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :list, :booking) do
      rows = Bookings.list_for_household(actor.household_id, scope: scope(params["scope"]))
      json(conn, BookingsJSON.collection(Enum.map(rows, &BookingsJSON.entry/1)))
    end
  end

  operation(:create,
    summary: "Book a player into a session",
    request_body: {"Booking", "application/json", S.create_request()},
    responses: [
      created: {"Booking", "application/json", S.booking()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Not bookable", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/bookings"
  def create(conn, params) do
    actor = actor(conn)
    attrs = body(params)

    with :ok <- Policy.authorize(actor, :book, :booking),
         {:ok, booking} <-
           Bookings.book(actor, attrs["player_id"], attrs["session_id"], method: attrs["method"]) do
      conn |> put_status(:created) |> json(BookingsJSON.booking(booking))
    end
  end

  operation(:cancel_preview,
    summary: "Preview the outcome of cancelling a booking",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Cancel preview", "application/json", S.cancel_preview()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/bookings/:id/cancel-preview"
  def cancel_preview(conn, %{"id" => id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :cancel_preview, :booking),
         {:ok, result} <- Bookings.cancel_preview(actor, id) do
      json(conn, BookingsJSON.cancel_preview(result))
    end
  end

  operation(:cancel,
    summary: "Cancel a booking",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Cancel", "application/json", S.cancel_request()},
    responses: [
      ok: {"Booking", "application/json", S.booking()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/bookings/:id/cancel"
  def cancel(conn, %{"id" => id} = params) do
    actor = actor(conn)
    attrs = Map.get(params, "cancel", params)

    with :ok <- Policy.authorize(actor, :cancel, :booking),
         {:ok, booking} <- Bookings.cancel(actor, id, reason: attrs["reason"]) do
      json(conn, BookingsJSON.booking(booking))
    end
  end

  operation(:rebook_options,
    summary: "List sessions a booking may be rebooked into",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Rebook options", "application/json", S.rebook_options()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/bookings/:id/rebook-options"
  def rebook_options(conn, %{"id" => id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :rebook_options, :booking),
         {:ok, result} <- Bookings.rebook_options(actor, id) do
      json(conn, BookingsJSON.rebook_options(result))
    end
  end

  operation(:rebook,
    summary: "Rebook a booking into another session",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Rebook", "application/json", S.rebook_request()},
    responses: [
      created: {"Booking", "application/json", S.booking()},
      unprocessable_entity: {"Not rebookable", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/bookings/:id/rebook"
  def rebook(conn, %{"id" => id} = params) do
    actor = actor(conn)
    attrs = Map.get(params, "rebook", params)

    with :ok <- Policy.authorize(actor, :rebook, :booking),
         {:ok, booking} <- Bookings.rebook(actor, id, attrs["target_session_id"], []) do
      conn |> put_status(:created) |> json(BookingsJSON.booking(booking))
    end
  end

  defp actor(conn), do: conn.assigns[:current_customer_actor]

  defp scope(nil), do: :all
  defp scope("upcoming"), do: :upcoming
  defp scope("past"), do: :past
  defp scope(_), do: :all

  defp body(params), do: Map.get(params, "booking", params)
end
