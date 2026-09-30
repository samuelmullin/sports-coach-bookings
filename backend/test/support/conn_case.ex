defmodule SportsCoachBookingsWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SportsCoachBookingsWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.DataCase

  using do
    quote do
      # The default endpoint for testing
      @endpoint SportsCoachBookingsWeb.Endpoint

      use SportsCoachBookingsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import SportsCoachBookings.Factory
      import SportsCoachBookingsWeb.ConnCase
    end
  end

  setup tags do
    DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Sets the request host to `{slug}.localhost`."
  def with_host(conn, slug), do: %{conn | host: "#{slug}.localhost"}

  @doc """
  Returns a conn for a staff actor in `tenant`. Auth is faked by assigning the
  actor; real auth plugs are added by WP-01.
  """
  def staff_conn(conn, tenant, role \\ :owner) do
    actor =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: tenant.id,
        role: role
      )

    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_staff_actor, actor)
    |> Plug.Conn.assign(:tenant, tenant)
  end

  @doc "Returns a conn for a customer actor in `tenant`."
  def customer_conn(conn, tenant) do
    actor =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: Ecto.UUID.generate(),
        tenant_id: tenant.id
      )

    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_customer_actor, actor)
    |> Plug.Conn.assign(:tenant, tenant)
  end
end
