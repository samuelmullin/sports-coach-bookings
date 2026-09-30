defmodule SportsCoachBookingsWeb.Plugs.FetchStaffUser do
  @moduledoc """
  Resolves the current staff user from the session cookie (global identity).

  Non-halting: anonymous requests pass through with no assigned user. Use
  `RequireStaffUser` when a route needs a logged-in user.
  """

  import Plug.Conn

  alias SportsCoachBookings.Staff.StaffUser
  alias SportsCoachBookingsWeb.Staff.Auth

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = fetch_session(conn)

    case conn.assigns[:current_staff_user] do
      %StaffUser{} ->
        conn

      _ ->
        case Auth.current_staff_user(conn) do
          %StaffUser{} = staff_user -> assign(conn, :current_staff_user, staff_user)
          nil -> conn
        end
    end
  end
end
