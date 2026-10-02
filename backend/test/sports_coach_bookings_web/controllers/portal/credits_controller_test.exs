defmodule SportsCoachBookingsWeb.Portal.CreditsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Credits

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  defp customer(conn, tenant, household) do
    actor =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: household,
        tenant_id: tenant.id
      )

    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_customer_actor, actor)
    |> Plug.Conn.assign(:tenant, tenant)
  end

  test "shows the caller's own household balance, lots, and ledger", %{conn: conn, tenant: tenant} do
    household = insert(:household).id

    {:ok, _lot} =
      Credits.grant_complimentary(nil, household, %{amount: 4, note: "goodwill"})

    conn = customer(conn, tenant, household)

    balance = conn |> get("/api/portal/credits") |> json_response(200)
    assert [%{"offering_id" => "any", "amount" => 4}] = balance["data"]

    lots = conn |> get("/api/portal/credits/lots") |> json_response(200)
    assert [%{"remaining" => 4}] = lots["data"]

    ledger = conn |> get("/api/portal/credits/ledger") |> json_response(200)
    assert [%{"reason" => "grant", "delta" => 4}] = ledger["data"]
  end

  test "cannot see another household's credits", %{conn: conn, tenant: tenant} do
    mine = Ecto.UUID.generate()
    theirs = Ecto.UUID.generate()

    {:ok, _} = Credits.grant_complimentary(nil, mine, %{amount: 1})
    {:ok, _} = Credits.grant_complimentary(nil, theirs, %{amount: 9})

    balance =
      conn
      |> customer(tenant, mine)
      |> get("/api/portal/credits")
      |> json_response(200)

    assert [%{"amount" => 1}] = balance["data"]
  end

  test "an anonymous caller is forbidden", %{conn: conn, tenant: tenant} do
    resp = conn |> with_host(tenant.slug) |> get("/api/portal/credits")
    assert json_response(resp, 403)["error"]["code"] == "forbidden"
  end
end
