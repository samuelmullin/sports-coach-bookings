defmodule SportsCoachBookingsWeb.Portal.Household.HouseholdController do
  @moduledoc "Customer household: members, invitations, leaving, and primary transfer."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.Policy
  alias SportsCoachBookingsWeb.Customers.Helpers
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:show,
    summary: "Get the current household with its members",
    responses: [
      ok: {"Household", "application/json", Schemas.household_detail()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/household"
  def show(conn, _params) do
    actor = Helpers.actor(conn)

    with :ok <- Policy.authorize(actor, :get, :household) do
      json(conn, CustomersJSON.household_detail(Customers.household_detail(actor.household_id)))
    end
  end

  operation(:invite,
    summary: "Invite another adult to co-manage the household",
    request_body: {"Invite", "application/json", Schemas.invite_request()},
    responses: [
      created: {"Invite", "application/json", Schemas.invite_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      conflict: {"Already a member", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/household/invites"
  def invite(conn, params) do
    actor = Helpers.actor(conn)

    with :ok <- Policy.authorize(actor, :invite, :household),
         {:ok, %{invite: invite, token: token}} <-
           Customers.invite_member(actor, Helpers.body(params, "invite")) do
      conn
      |> put_status(:created)
      |> json(%{invite: CustomersJSON.invite(invite), token: token})
    end
  end

  operation(:invites,
    summary: "List pending household invitations",
    responses: [
      ok: {"Invites", "application/json", Schemas.invite_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/household/invites"
  def invites(conn, _params) do
    actor = Helpers.actor(conn)

    with :ok <- Policy.authorize(actor, :list_invites, :household) do
      invites = Customers.list_pending_invites(actor.household_id)
      json(conn, %{data: Enum.map(invites, &CustomersJSON.invite/1)})
    end
  end

  operation(:remove_member,
    summary: "Remove a manager (primary members only)",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      no_content: {"Removed", nil, nil},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/portal/household/members/:id"
  def remove_member(conn, %{"id" => id}) do
    actor = Helpers.actor(conn)

    with {:ok, member} <- fetch_member(id),
         :ok <- Policy.authorize(actor, :remove_member, member),
         {:ok, _} <- Customers.remove_member(actor, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:leave,
    summary: "Leave the household (primary members must transfer first)",
    responses: [
      no_content: {"Left", nil, nil},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/household/leave"
  def leave(conn, _params) do
    actor = Helpers.actor(conn)

    with :ok <- Policy.authorize(actor, :leave, :household),
         {:ok, _} <- Customers.leave_household(actor) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:transfer_primary,
    summary: "Transfer the primary role to another household member",
    request_body: {"Transfer", "application/json", Schemas.transfer_primary_request()},
    responses: [
      ok: {"Member", "application/json", Schemas.household_member()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/household/transfer_primary"
  def transfer_primary(conn, %{"member_id" => member_id}) do
    actor = Helpers.actor(conn)

    with {:ok, member} <- fetch_member(member_id),
         :ok <- Policy.authorize(actor, :transfer_primary, member),
         {:ok, promoted} <- Customers.transfer_primary(actor, member_id) do
      json(conn, CustomersJSON.member(promoted))
    end
  end

  def transfer_primary(_conn, _params),
    do: {:error, {:validation_error, "member_id is required"}}

  defp fetch_member(id) do
    case Customers.get_member(id) do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end
end
