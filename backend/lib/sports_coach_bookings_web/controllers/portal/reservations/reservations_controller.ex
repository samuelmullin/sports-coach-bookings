defmodule SportsCoachBookingsWeb.Portal.Reservations.ReservationsController do
  @moduledoc """
  Portal: anonymous guest reservation holds, and their conversion to bookings.

  `POST /api/portal/reservations` is anonymous; the returned opaque token is the
  credential for `show`/`extend`/`delete`. `convert` requires an authenticated
  customer (the guest has signed up) and uses that customer's household.
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Reservations
  alias SportsCoachBookingsWeb.ReservationsJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Reservations, as: S

  tags(["portal"])

  operation(:create,
    summary: "Hold seats for an anonymous guest",
    request_body: {"Reservation", "application/json", S.create_request()},
    responses: [
      created: {"Reservation", "application/json", S.create_response()},
      conflict: {"A session is full", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid session", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/reservations"
  def create(conn, params) do
    with {:ok, result} <- Reservations.create(body(params)) do
      conn |> put_status(:created) |> json(ReservationsJSON.created(result))
    end
  end

  operation(:show,
    summary: "Fetch a guest reservation",
    parameters: [
      id: [in: :path, type: :string, required: true],
      "x-reservation-token": [in: :header, type: :string, required: true]
    ],
    responses: [
      ok: {"Reservation", "application/json", S.reservation()},
      unauthorized: {"Missing token", "application/json", ErrorResponse},
      not_found: {"Unknown reservation", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/reservations/:id"
  def show(conn, %{"id" => _id}) do
    json(conn, ReservationsJSON.reservation(conn.assigns.current_reservation))
  end

  operation(:extend,
    summary: "Extend a guest reservation",
    parameters: [
      id: [in: :path, type: :string, required: true],
      "x-reservation-token": [in: :header, type: :string, required: true]
    ],
    responses: [
      ok: {"Reservation", "application/json", S.extend_response()},
      conflict: {"Reservation expired", "application/json", ErrorResponse},
      not_found: {"Unknown reservation", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/reservations/:id/extend"
  def extend(conn, %{"id" => id}) do
    with {:ok, reservation} <- Reservations.extend(id, conn.assigns.reservation_token) do
      json(conn, ReservationsJSON.extend(reservation))
    end
  end

  operation(:delete,
    summary: "Release a guest reservation",
    parameters: [
      id: [in: :path, type: :string, required: true],
      "x-reservation-token": [in: :header, type: :string, required: true]
    ],
    responses: [
      no_content: "Released",
      not_found: {"Unknown reservation", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/portal/reservations/:id"
  def delete(conn, %{"id" => id}) do
    with :ok <- Reservations.release(id, conn.assigns.reservation_token) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:convert,
    summary: "Convert a guest reservation into bookings (authenticated)",
    parameters: [
      id: [in: :path, type: :string, required: true],
      "x-reservation-token": [in: :header, type: :string, required: true]
    ],
    request_body: {"Conversion", "application/json", S.convert_request()},
    responses: [
      ok: {"Bookings", "application/json", S.convert_response()},
      forbidden: {"Email unconfirmed", "application/json", ErrorResponse},
      conflict: {"Reservation expired", "application/json", ErrorResponse},
      unprocessable_entity: {"Not convertible", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/reservations/:id/convert"
  def convert(conn, %{"id" => id} = params) do
    actor = conn.assigns.current_customer_actor
    attrs = body(params)

    with :ok <- require_confirmed(actor),
         {:ok, result} <-
           Reservations.convert(
             id,
             conn.assigns.reservation_token,
             actor,
             actor.household_id,
             attrs["assignments"]
           ) do
      json(conn, ReservationsJSON.convert(result))
    end
  end

  defp require_confirmed(%CustomerActor{customer_user: %CustomerUser{} = user}),
    do: Customers.require_confirmed(user)

  defp require_confirmed(_actor), do: :ok

  defp body(params), do: Map.get(params, "reservation", params)
end
