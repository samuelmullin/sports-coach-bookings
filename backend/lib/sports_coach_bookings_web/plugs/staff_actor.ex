defmodule SportsCoachBookingsWeb.Plugs.StaffActor do
  @moduledoc """
  Builds `SportsCoachBookings.Core.StaffActor` for `/api/staff/*` requests.

  Requires a logged-in global staff user **and** an active membership in the
  tenant resolved from the host. Halts with `403` when either is missing (no
  membership, or anonymous), so a caller never learns which.
  """

  import Plug.Conn

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Staff.Membership
  alias SportsCoachBookings.Staff.StaffUser
  alias SportsCoachBookingsWeb.Staff.Auth

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = fetch_session(conn)

    if match?(%StaffActor{}, conn.assigns[:current_staff_actor]) do
      conn
    else
      authenticate(conn)
    end
  end

  defp authenticate(conn) do
    tenant = conn.assigns[:tenant]
    staff_user = conn.assigns[:current_staff_user] || Auth.current_staff_user(conn)
    build(conn, tenant, staff_user)
  end

  defp build(conn, %Tenant{} = tenant, %StaffUser{} = staff_user) do
    case Staff.get_active_membership(staff_user.id) do
      %Membership{} = membership ->
        actor =
          StaffActor.new(
            staff_user_id: staff_user.id,
            membership: membership,
            tenant_id: tenant.id,
            role: membership.role
          )

        conn
        |> assign(:current_staff_user, staff_user)
        |> assign(:current_staff_actor, actor)

      nil ->
        error(conn, 403, "forbidden", "No active membership for this tenant")
    end
  end

  defp build(conn, _tenant, _staff_user) do
    error(conn, 403, "forbidden", "An active membership for this tenant is required")
  end

  defp error(conn, status, code, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code, message: message, details: %{}}}))
    |> halt()
  end
end
