defmodule SportsCoachBookingsWeb.Plugs.FetchCustomerUser do
  @moduledoc """
  Resolves the current customer user from the host-only portal session cookie.

  Non-halting: anonymous requests (or requests with no resolved tenant, like the
  platform host) pass through with no assigned user. Use `RequireCustomerActor`
  when a route needs an authenticated customer.
  """

  import Plug.Conn

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookingsWeb.Portal.Auth

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = fetch_session(conn)

    case conn.assigns[:current_customer_user] do
      %CustomerUser{} ->
        conn

      _ ->
        fetch(conn)
    end
  end

  defp fetch(conn) do
    if TenantContext.get_tenant_id() do
      case Auth.current_customer_user(conn) do
        %CustomerUser{} = customer_user ->
          assign(conn, :current_customer_user, customer_user)

        nil ->
          conn
      end
    else
      conn
    end
  end
end
