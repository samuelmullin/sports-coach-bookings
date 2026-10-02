defmodule SportsCoachBookingsWeb.Portal.PrivacyControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias Phoenix.ConnTest
  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Players

  @password "a very long password"

  defp host(conn, slug), do: %{conn | host: "#{slug}.localhost"}

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  # Registers + logs in on tenant `acme`; returns the logged-in conn and household id.
  defp signed_in(conn) do
    tenant = insert(:tenant, slug: "acme")

    signup =
      conn
      |> host("acme")
      |> json_post("/api/portal/registrations", %{
        first_name: "Dana",
        last_name: "Reyes",
        email: "dana@example.com",
        phone: "+19025550111",
        password: @password,
        accept_terms: true,
        accept_privacy: true
      })

    assert json_response(signup, 201)

    login =
      build_conn()
      |> host("acme")
      |> json_post("/api/portal/session", %{email: "dana@example.com", password: @password})

    assert json_response(login, 201)

    DataCase.put_tenant(tenant)
    user = SportsCoachBookings.Customers.get_customer_user_by_email("dana@example.com")
    household = SportsCoachBookings.Customers.household_for_user(user)

    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household.id,
        first_name: "Sam",
        last_name: "Reyes",
        date_of_birth: ~D[2015-05-01]
      })

    {:ok, _} =
      Players.upsert_medical_info(nil, player, %{allergies: "peanuts"})

    {ConnTest.recycle(login) |> host("acme"), player}
  end

  test "export returns the household's data including medical info", %{conn: conn} do
    {authed, player} = signed_in(conn)

    resp = get(authed, "/api/portal/account/export")
    body = json_response(resp, 200)

    # Served as a file download that must not be cached.
    assert [disposition] = get_resp_header(resp, "content-disposition")
    assert disposition =~ ~s(attachment; filename="household-data.json")
    assert ["no-store"] = get_resp_header(resp, "cache-control")

    assert [%{"player" => %{"id" => id}, "medical_info" => %{"allergies" => "peanuts"}}] =
             body["players"]

    assert id == player.id
    assert [%{"customer_user" => %{"email" => "dana@example.com"}}] = body["household"]["members"]
  end

  test "export requires a customer session", %{conn: conn} do
    insert(:tenant, slug: "acme")
    resp = conn |> host("acme") |> get("/api/portal/account/export")
    assert resp.status in [401, 403]
  end

  test "erase requires the literal confirmation and the right password", %{conn: conn} do
    {authed, player} = signed_in(conn)

    no_confirm = json_post(authed, "/api/portal/account/erase", %{password: @password})
    assert json_response(no_confirm, 422)["error"]["code"] == "validation_error"

    wrong =
      json_post(authed, "/api/portal/account/erase", %{
        password: "not the password",
        confirm: "ERASE"
      })

    assert json_response(wrong, 403)["error"]["code"] == "invalid_password"
    assert Players.get_player!(player.id)
  end

  test "erase wipes the household and ends the session", %{conn: conn} do
    {authed, player} = signed_in(conn)

    resp =
      json_post(authed, "/api/portal/account/erase", %{password: @password, confirm: "ERASE"})

    body = json_response(resp, 200)
    assert body["players"] == 1
    assert body["waiver_pdfs"] == 0

    assert_raise Ecto.NoResultsError, fn -> Players.get_player!(player.id) end

    relogin =
      build_conn()
      |> host("acme")
      |> json_post("/api/portal/session", %{email: "dana@example.com", password: @password})

    assert json_response(relogin, 401)

    after_erase = ConnTest.recycle(resp) |> host("acme") |> get("/api/portal/account/export")
    assert after_erase.status in [401, 403]
  end
end
