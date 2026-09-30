defmodule SportsCoachBookingsWeb.Staff.Team.MembersController do
  @moduledoc "Team management: list, invite, change role, remove."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Staff.Policy
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.StaffJSON

  tags(["staff"])

  operation(:index,
    summary: "List the team",
    responses: [
      ok: {"Team", "application/json", Api.membership_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/team"
  def index(conn, _params) do
    with :ok <- authorize(conn, :list, :team) do
      data = Enum.map(Staff.list_team(), &StaffJSON.membership_with_user/1)
      json(conn, %{data: data})
    end
  end

  operation(:invite,
    summary: "Invite a staff member",
    request_body: {"Invite", "application/json", Api.invite_request()},
    responses: [
      created: {"Invite", "application/json", Api.invite_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      conflict: {"Already a member", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/team/invites"
  def invite(conn, params) do
    with {:ok, role} <- role(params["role"]),
         :ok <- authorize(conn, {:invite, role}, :team),
         {:ok, %{invite: invite, token: token}} <-
           Staff.invite_staff(actor(conn), %{email: params["email"], role: role}) do
      conn
      |> put_status(:created)
      |> json(%{invite: StaffJSON.invite(invite), token: token})
    end
  end

  operation(:invites,
    summary: "List pending invites",
    responses: [ok: {"Invites", "application/json", Api.invite_list()}]
  )

  @doc "GET /api/staff/team/invites"
  def invites(conn, _params) do
    with :ok <- authorize(conn, :list, :team) do
      json(conn, %{data: Enum.map(Staff.list_invites(), &StaffJSON.invite/1)})
    end
  end

  operation(:update,
    summary: "Change a member's role",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Role", "application/json", Api.role_update_request()},
    responses: [
      ok: {"Membership", "application/json", Api.membership()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      conflict: {"Last owner", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/team/members/:id"
  def update(conn, %{"id" => id} = params) do
    with {:ok, role} <- role(params["role"]),
         :ok <- authorize(conn, {:change_role, role}, :team),
         {:ok, membership} <- Staff.change_role(actor(conn), id, role) do
      json(conn, StaffJSON.membership(membership))
    end
  end

  operation(:delete,
    summary: "Remove a member (soft)",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Membership", "application/json", Api.membership()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      conflict: {"Last owner", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/staff/team/members/:id"
  def delete(conn, %{"id" => id}) do
    membership = Staff.get_membership!(id)

    with :ok <- authorize(conn, {:remove, membership.role}, :team),
         {:ok, removed} <- Staff.remove_membership(actor(conn), id) do
      json(conn, StaffJSON.membership(removed))
    end
  end

  defp authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp role(role) when role in [:owner, :admin, :coach], do: {:ok, role}
  defp role("owner"), do: {:ok, :owner}
  defp role("admin"), do: {:ok, :admin}
  defp role("coach"), do: {:ok, :coach}
  defp role(_), do: {:error, :invalid_role}
end
