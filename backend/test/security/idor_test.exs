defmodule SportsCoachBookings.Security.IdorTest do
  @moduledoc """
  WP-19 IDOR sweep: for representative ID-bearing routes, a caller from another
  tenant or another household must get `404`/`403`, never the resource.
  """

  use SportsCoachBookingsWeb.ConnCase, async: true

  import SportsCoachBookings.DataCase, only: [put_tenant: 1]

  alias SportsCoachBookings.Core.CustomerActor

  setup do
    tenant_a = insert(:tenant)
    tenant_b = insert(:tenant)
    %{tenant_a: tenant_a, tenant_b: tenant_b}
  end

  describe "staff routes" do
    test "cannot read a venue from another tenant", %{conn: conn, tenant_a: a, tenant_b: b} do
      venue = insert_in(b, fn -> insert(:venue, tenant_id: b.id) end)

      assert conn
             |> staff_conn(a)
             |> get(~p"/api/staff/catalog/venues/#{venue.id}")
             |> response(404)
    end

    test "cannot read a player from another tenant", %{conn: conn, tenant_a: a, tenant_b: b} do
      player = insert_in(b, fn -> insert(:player, tenant_id: b.id) end)

      assert conn
             |> staff_conn(a)
             |> get(~p"/api/staff/players/#{player.id}")
             |> response(404)
    end

    test "cannot read an order from another tenant", %{conn: conn, tenant_a: a, tenant_b: b} do
      order = insert_in(b, fn -> insert(:order, tenant_id: b.id) end)

      assert conn
             |> staff_conn(a)
             |> get(~p"/api/staff/orders/#{order.id}")
             |> response(404)
    end

    test "cannot read a broadcast from another tenant", %{conn: conn, tenant_a: a, tenant_b: b} do
      broadcast = insert_in(b, fn -> insert(:broadcast, tenant_id: b.id) end)

      assert conn
             |> staff_conn(a)
             |> get(~p"/api/staff/broadcasts/#{broadcast.id}")
             |> response(404)
    end
  end

  describe "portal routes" do
    test "a household cannot read another household's player", %{conn: conn, tenant_a: a} do
      household = insert_in(a, fn -> insert(:household, tenant_id: a.id) end)
      other_household = insert_in(a, fn -> insert(:household, tenant_id: a.id) end)

      player =
        insert_in(a, fn -> insert(:player, tenant_id: a.id, household_id: other_household.id) end)

      conn =
        conn
        |> customer_conn_in(a, household.id)

      assert get(conn, ~p"/api/portal/players/#{player.id}").status in [403, 404]
    end

    test "a household can read its own player", %{conn: conn, tenant_a: a} do
      household = insert_in(a, fn -> insert(:household, tenant_id: a.id) end)

      player =
        insert_in(a, fn -> insert(:player, tenant_id: a.id, household_id: household.id) end)

      conn = customer_conn_in(conn, a, household.id)

      assert get(conn, ~p"/api/portal/players/#{player.id}") |> response(200)
    end

    test "a customer cannot read another tenant's player", %{conn: conn, tenant_a: a, tenant_b: b} do
      household = insert_in(a, fn -> insert(:household, tenant_id: a.id) end)

      player =
        insert_in(b, fn ->
          household_b = insert(:household, tenant_id: b.id)
          insert(:player, tenant_id: b.id, household_id: household_b.id)
        end)

      conn = customer_conn_in(conn, a, household.id)
      assert get(conn, ~p"/api/portal/players/#{player.id}").status in [403, 404]
    end

    test "a customer cannot read another household's order", %{conn: conn, tenant_a: a} do
      household = insert_in(a, fn -> insert(:household, tenant_id: a.id) end)
      other = insert_in(a, fn -> insert(:household, tenant_id: a.id) end)

      order =
        insert_in(a, fn ->
          insert(:order, tenant_id: a.id, household_id: other.id)
        end)

      conn = customer_conn_in(conn, a, household.id)
      assert get(conn, ~p"/api/portal/orders/#{order.id}").status in [403, 404]
    end
  end

  # Inserts within tenant `tenant`'s context and RLS GUC.
  defp insert_in(tenant, fun) do
    put_tenant(tenant)
    record = fun.()
    put_tenant(tenant)
    record
  end

  defp customer_conn_in(conn, tenant, household_id) do
    actor =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: household_id,
        tenant_id: tenant.id
      )

    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_customer_actor, actor)
    |> Plug.Conn.assign(:tenant, tenant)
  end
end
