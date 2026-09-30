defmodule SportsCoachBookingsWeb.Staff.InvitesController do
  @moduledoc """
  Invite inspection and acceptance. Tenant-resolved; no membership required
  (the token is the credential). Authentication is optional: a logged-in staff
  user joins, otherwise the invite email is trusted and an account is created.
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Staff.StaffInvite
  alias SportsCoachBookings.Staff.StaffUser
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Staff.Auth
  alias SportsCoachBookingsWeb.StaffJSON

  tags(["staff"])

  operation(:show,
    summary: "Inspect a pending invite",
    parameters: [token: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Invite", "application/json", Api.invite_show_response()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/invites/:token"
  def show(conn, %{"token" => token}) do
    case Staff.get_invite_by_token(token) do
      nil ->
        {:error, :not_found}

      %StaffInvite{} = invite ->
        json(conn, %{
          email: invite.email,
          role: invite.role,
          tenant_name: conn.assigns.tenant.name,
          expired: StaffInvite.expired?(invite)
        })
    end
  end

  operation(:accept,
    summary: "Accept an invite",
    parameters: [token: [in: :path, type: :string, required: true]],
    request_body: {"New account password", "application/json", Api.accept_invite_request()},
    responses: [
      created: {"Joined", "application/json", Api.membership_result()},
      not_found: {"Not found", "application/json", ErrorResponse},
      gone: {"Expired", "application/json", ErrorResponse},
      conflict: {"Already a member", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/invites/:token/accept"
  def accept(conn, %{"token" => token} = params) do
    opts =
      case conn.assigns[:current_staff_user] do
        %StaffUser{} = staff_user -> [staff_user: staff_user]
        _ -> []
      end

    case Staff.accept_invite(token, params, opts) do
      {:ok, %{membership: membership, staff_user: staff_user}} ->
        conn
        |> Auth.log_in_staff(staff_user)
        |> put_status(:created)
        |> json(%{
          membership: StaffJSON.membership(membership),
          staff_user: StaffJSON.staff_user(staff_user)
        })

      {:error, reason} ->
        {:error, reason}
    end
  end
end
