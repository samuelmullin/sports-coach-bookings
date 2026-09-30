defmodule SportsCoachBookingsWeb.Plugs.FetchCustomerActor do
  @moduledoc """
  Non-halting: assigns `:current_customer_actor` when the request has an
  authenticated customer user with a household, otherwise leaves the conn
  anonymous. Policy checks then decide whether the action is allowed.
  """

  import Plug.Conn

  alias SportsCoachBookingsWeb.Plugs.CustomerActor

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> fetch_session()
    |> CustomerActor.assign_actor()
  end
end
