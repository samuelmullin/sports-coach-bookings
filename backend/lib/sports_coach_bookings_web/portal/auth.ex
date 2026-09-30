defmodule SportsCoachBookingsWeb.Portal.Auth do
  @moduledoc """
  Session helpers for tenant-scoped customer authentication.

  The customer session is stored in the same signed cookie as the staff session
  but under a separate key (`"customer_token"`), and the token is resolved to a
  customer user **within the resolved tenant** on each request. Because customer
  tokens are tenant-owned (RLS), a token minted for tenant A never resolves on
  tenant B's host. See `docs/rfcs/20260928-customers-portal-session.md`.
  """

  alias Plug.Conn
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser

  @session_key "customer_token"

  @doc "Creates a session for `customer_user` and stores its token in the session."
  @spec log_in_customer(Conn.t(), CustomerUser.t()) :: Conn.t()
  def log_in_customer(%Conn{} = conn, %CustomerUser{} = customer_user) do
    {token, _record} = Customers.create_session_token(customer_user)

    conn
    |> Conn.configure_session(renew: true)
    |> Conn.put_session(@session_key, token)
    |> Conn.assign(:current_customer_user, customer_user)
  end

  @doc "Deletes the customer session token and clears it from the session."
  @spec log_out_customer(Conn.t()) :: Conn.t()
  def log_out_customer(%Conn{} = conn) do
    case Conn.get_session(conn, @session_key) do
      nil -> :ok
      token -> Customers.delete_session_token(token)
    end

    Conn.delete_session(conn, @session_key)
  end

  @doc "The customer user for the current session, or `nil`."
  @spec current_customer_user(Conn.t()) :: CustomerUser.t() | nil
  def current_customer_user(%Conn{} = conn) do
    case Conn.get_session(conn, @session_key) do
      nil ->
        nil

      token ->
        case Customers.get_customer_user_by_session_token(token) do
          {:ok, customer_user} -> customer_user
          :error -> nil
        end
    end
  end
end
