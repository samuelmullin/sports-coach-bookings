defmodule SportsCoachBookingsWeb.Plugs.RequireStaffUser do
  @moduledoc "Halts with `401` unless a staff user is authenticated."

  import Plug.Conn

  alias SportsCoachBookings.Staff.StaffUser

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if match?(%StaffUser{}, conn.assigns[:current_staff_user]) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        401,
        Jason.encode!(%{
          error: %{code: "unauthorized", message: "Unauthorized", details: %{}}
        })
      )
      |> halt()
    end
  end
end
