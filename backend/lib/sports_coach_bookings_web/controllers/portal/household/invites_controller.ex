defmodule SportsCoachBookingsWeb.Portal.Household.InvitesController do
  @moduledoc """
  Household invitation inspection and acceptance. Tenant-resolved; no customer
  session required (the token is the credential). If a customer is already
  logged in on this host they join with that account; otherwise the invite email
  is trusted and a pre-confirmed account is created from the supplied details.
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.HouseholdInvite
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Portal.Auth
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:show,
    summary: "Inspect a household invitation",
    parameters: [token: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Invite", "application/json", Schemas.invite_show()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/household_invites/:token"
  def show(conn, %{"token" => token}) do
    case Customers.get_invite_by_token(token) do
      nil ->
        {:error, :not_found}

      %HouseholdInvite{} = invite ->
        json(conn, %{
          email: invite.email,
          relationship: invite.relationship,
          tenant_name: conn.assigns.tenant.name,
          expired: HouseholdInvite.expired?(invite)
        })
    end
  end

  operation(:accept,
    summary: "Accept a household invitation",
    parameters: [token: [in: :path, type: :string, required: true]],
    request_body: {"Registration details", "application/json", Schemas.accept_invite_request()},
    responses: [
      created: {"Joined", "application/json", Schemas.accept_invite_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      gone: {"Expired", "application/json", ErrorResponse},
      conflict: {"Already a member", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/household_invites/:token/accept"
  def accept(conn, %{"token" => token} = params) do
    opts =
      case conn.assigns[:current_customer_user] do
        %CustomerUser{} = customer_user -> [customer_user: customer_user]
        _ -> []
      end

    attrs = Map.drop(params, ["token"])

    case Customers.accept_invite(token, attrs, opts) do
      {:ok, %{customer_user: customer_user, household: household, member: member}} ->
        conn
        |> Auth.log_in_customer(customer_user)
        |> put_status(:created)
        |> json(%{
          customer_user: CustomersJSON.customer_user(customer_user),
          household: CustomersJSON.household(household),
          member: CustomersJSON.member(member)
        })

      {:error, reason} ->
        {:error, reason}
    end
  end
end
