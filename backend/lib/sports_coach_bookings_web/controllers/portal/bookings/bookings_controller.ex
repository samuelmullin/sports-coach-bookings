defmodule SportsCoachBookingsWeb.Portal.Bookings.BookingsController do
  @moduledoc "Portal: book, list, cancel (with preview), and rebook household bookings."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Bookings.Policy
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookingsWeb.BookingsJSON
  alias SportsCoachBookingsWeb.Schemas.Bookings, as: S
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Scheduling, as: SchedulingSchemas

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
         :ok <- require_confirmed(actor),
         {:ok, booking} <-
           Bookings.book(actor, attrs["player_id"], attrs["session_id"], method: attrs["method"]) do
      conn |> put_status(:created) |> json(BookingsJSON.booking(booking))
    end
  end

  operation(:invitations,
    summary: "List the household's session invitations",
    responses: [ok: {"Invitations", "application/json", S.list(S.invitation())}]
  )

  @doc "GET /api/portal/bookings/invitations"
  def invitations(conn, _params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :invite, :booking) do
      data =
        actor.household_id |> Bookings.list_invitations() |> Enum.map(&BookingsJSON.invitation/1)

      json(conn, BookingsJSON.collection(data))
    end
  end

  operation(:partners,
    summary: "List previous accepted invitation partners",
    responses: [
      ok:
        {"Partners", "application/json",
         S.list(%OpenApiSpex.Schema{type: :object, additionalProperties: true})}
    ]
  )

  @doc "GET /api/portal/bookings/invitation-partners"
  def partners(conn, _params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :invite, :booking) do
      json(conn, BookingsJSON.collection(Bookings.invitation_partners(actor.household_id)))
    end
  end

  operation(:invite,
    summary: "Invite one player to a session",
    parameters: [session_id: [in: :path, type: :string, required: true]],
    request_body: {"Invitation", "application/json", S.invitation_create_request()},
    responses: [created: {"Invitation", "application/json", S.invitation_result()}]
  )

  @doc "POST /api/portal/bookings/sessions/:session_id/invitations"
  def invite(conn, %{"session_id" => session_id} = params) do
    actor = actor(conn)
    attrs = Map.get(params, "invitation", params)

    with :ok <- Policy.authorize(actor, :invite, :booking),
         :ok <- require_confirmed(actor),
         {:ok, result} <- Bookings.invite(actor, session_id, attrs) do
      conn
      |> put_status(:created)
      |> json(%{
        invitation: BookingsJSON.invitation(result.invitation),
        booking: result.booking && BookingsJSON.booking(result.booking)
      })
    end
  end

  operation(:cancel_invitation,
    summary: "Cancel a pending session invitation",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Cancelled invitation", "application/json", S.invitation()}]
  )

  @doc "DELETE /api/portal/bookings/invitations/:id"
  def cancel_invitation(conn, %{"id" => id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :invite, :booking),
         {:ok, invitation} <- Bookings.cancel_invitation(actor, id) do
      json(conn, BookingsJSON.invitation(invitation))
    end
  end

  operation(:resend_invitation,
    summary: "Rotate the token and resend a pending session invitation",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Resent invitation", "application/json", S.invitation()}]
  )

  @doc "POST /api/portal/bookings/invitations/:id/resend"
  def resend_invitation(conn, %{"id" => id}) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :invite, :booking),
         :ok <- require_confirmed(actor),
         {:ok, result} <- Bookings.resend_invitation(actor, id) do
      json(conn, BookingsJSON.invitation(result.invitation))
    end
  end

  operation(:show_invitation,
    summary: "View a session invitation",
    parameters: [token: [in: :path, type: :string, required: true]],
    responses: [ok: {"Invitation", "application/json", S.invitation()}]
  )

  @doc "GET /api/portal/session_invitations/:token"
  def show_invitation(conn, %{"token" => token}) do
    with {:ok, invitation} <- Bookings.invitation_by_token(token) do
      json(conn, BookingsJSON.invitation(invitation))
    end
  end

  operation(:accept_invitation,
    summary: "Accept a session invitation",
    parameters: [token: [in: :path, type: :string, required: true]],
    request_body: {"Acceptance", "application/json", S.invitation_accept_request()},
    responses: [created: {"Accepted invitation", "application/json", S.invitation_result()}]
  )

  @doc "POST /api/portal/bookings/session_invitations/:token/accept"
  def accept_invitation(conn, %{"token" => token} = params) do
    actor = actor(conn)
    attrs = Map.get(params, "invitation", params)

    with :ok <- Policy.authorize(actor, :accept_invitation, :booking),
         :ok <- require_confirmed(actor),
         {:ok, result} <-
           Bookings.accept_invitation(actor, token, attrs["player_id"], attrs["method"]) do
      conn
      |> put_status(:created)
      |> json(%{
        invitation: BookingsJSON.invitation(result.invitation),
        booking: BookingsJSON.booking(result.booking)
      })
    end
  end

  operation(:convert_private,
    summary: "Convert an empty public session into a private party",
    parameters: [session_id: [in: :path, type: :string, required: true]],
    request_body: {"Private party", "application/json", S.private_conversion_request()},
    responses: [
      ok: {"Private session", "application/json", SchedulingSchemas.session()}
    ]
  )

  @doc "POST /api/portal/bookings/sessions/:session_id/convert-private"
  def convert_private(conn, %{"session_id" => session_id} = params) do
    actor = actor(conn)
    attrs = Map.get(params, "private_session", params)

    with :ok <- Policy.authorize(actor, :convert_private, :session),
         :ok <- require_confirmed(actor),
         {:ok, session} <-
           Bookings.convert_session_to_private(actor, session_id, attrs["party_size"]) do
      json(conn, SportsCoachBookingsWeb.SchedulingJSON.session(session))
    end
  end

  operation(:request_private,
    summary: "Request a new operator-approved private session",
    request_body: {"Private session request", "application/json", S.private_session_request()},
    responses: [
      created: {"Request", "application/json", S.private_session_request_response()}
    ]
  )

  @doc "POST /api/portal/bookings/private-session-requests"
  def request_private(conn, params) do
    actor = actor(conn)
    attrs = Map.get(params, "private_session_request", params)

    with :ok <- Policy.authorize(actor, :request_private, :session),
         :ok <- require_confirmed(actor),
         {:ok, request} <-
           Bookings.request_private_session(actor, attrs["offering_id"], attrs) do
      conn
      |> put_status(:created)
      |> json(BookingsJSON.private_session_request(request))
    end
  end

  operation(:private_requests,
    summary: "List the household's private-session requests",
    responses: [
      ok:
        {"Private-session requests", "application/json",
         S.list(S.private_session_request_response())}
    ]
  )

  @doc "GET /api/portal/bookings/private-session-requests"
  def private_requests(conn, _params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :request_private, :session) do
      data =
        actor.household_id
        |> Bookings.list_private_session_requests()
        |> Enum.map(&BookingsJSON.private_session_request/1)

      json(conn, BookingsJSON.collection(data))
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

  defp require_confirmed(%CustomerActor{customer_user: %CustomerUser{} = user}),
    do: Customers.require_confirmed(user)

  defp require_confirmed(_actor), do: :ok

  defp actor(conn), do: conn.assigns[:current_customer_actor]

  defp scope(nil), do: :all
  defp scope("upcoming"), do: :upcoming
  defp scope("past"), do: :past
  defp scope(_), do: :all

  defp body(params), do: Map.get(params, "booking", params)
end
