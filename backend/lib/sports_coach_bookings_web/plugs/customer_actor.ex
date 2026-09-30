defmodule SportsCoachBookingsWeb.Plugs.CustomerActor do
  @moduledoc """
  Builds `SportsCoachBookings.Core.CustomerActor` for `/api/portal/*` requests.

  Requires an authenticated customer user (resolved from the host-only portal
  cookie by `FetchCustomerUser`) **and** a household in the host-resolved tenant.
  Halts with `403` when either is missing, so a caller never learns which.
  """

  import Plug.Conn

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.Household

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = fetch_session(conn)

    case assign_actor(conn) do
      %{assigns: %{current_customer_actor: %CustomerActor{}}} = conn ->
        conn

      conn ->
        error(conn, 403, "forbidden", "A customer session for this tenant is required")
    end
  end

  @doc """
  Assigns `:current_customer_actor` when the conn has an authenticated customer
  user with a household; otherwise returns the conn unchanged (non-halting).
  """
  @spec assign_actor(Plug.Conn.t()) :: Plug.Conn.t()
  def assign_actor(%Plug.Conn{} = conn) do
    case conn.assigns do
      %{current_customer_actor: %CustomerActor{}} ->
        conn

      %{current_customer_user: %CustomerUser{} = customer_user} ->
        build(conn, customer_user)

      _ ->
        conn
    end
  end

  defp build(conn, %CustomerUser{} = customer_user) do
    case Customers.household_for_user(customer_user) do
      %Household{} = household ->
        actor =
          CustomerActor.new(
            customer_user_id: customer_user.id,
            household_id: household.id,
            tenant_id: customer_user.tenant_id,
            customer_user: customer_user,
            household: household
          )

        assign(conn, :current_customer_actor, actor)

      nil ->
        conn
    end
  end

  defp error(conn, status, code, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code, message: message, details: %{}}}))
    |> halt()
  end
end
