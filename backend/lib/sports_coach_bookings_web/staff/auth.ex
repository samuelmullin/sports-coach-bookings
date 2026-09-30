defmodule SportsCoachBookingsWeb.Staff.Auth do
  @moduledoc """
  Session helpers for global staff authentication.

  The staff session is a cookie (`Plug.Session`) carrying only an opaque session
  token; the token is resolved to a staff user on each request. The cookie is
  scoped to the configured base domain so one login works across
  `{slug}.<base_domain>`.
  """

  alias Plug.Conn
  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Staff.StaffUser

  @session_key "staff_token"

  @doc "Creates a session for `staff_user` and stores its token in the session."
  @spec log_in_staff(Conn.t(), StaffUser.t()) :: Conn.t()
  def log_in_staff(%Conn{} = conn, %StaffUser{} = staff_user) do
    {token, _record} = Staff.create_session_token(staff_user)

    conn
    |> Conn.configure_session(renew: true)
    |> Conn.put_session(@session_key, token)
    |> Conn.assign(:current_staff_user, staff_user)
  end

  @doc "Deletes the staff session token and clears it from the session."
  @spec log_out_staff(Conn.t()) :: Conn.t()
  def log_out_staff(%Conn{} = conn) do
    case Conn.get_session(conn, @session_key) do
      nil -> :ok
      token -> Staff.delete_session_token(token)
    end

    Conn.delete_session(conn, @session_key)
  end

  @doc "The staff user for the current session, or `nil`."
  @spec current_staff_user(Conn.t()) :: StaffUser.t() | nil
  def current_staff_user(%Conn{} = conn) do
    case Conn.get_session(conn, @session_key) do
      nil ->
        nil

      token ->
        case Staff.get_staff_user_by_session_token(token) do
          {:ok, staff_user} -> staff_user
          :error -> nil
        end
    end
  end
end
