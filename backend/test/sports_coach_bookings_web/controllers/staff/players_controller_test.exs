defmodule SportsCoachBookingsWeb.Staff.PlayersControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Repo

  defmodule VisibleCoachAccess do
    @moduledoc false
    def player_visible?(_actor, _player_id), do: true
  end

  defmodule HiddenCoachAccess do
    @moduledoc false
    def player_visible?(_actor, _player_id), do: false
  end

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)

    previous = Application.get_env(:sports_coach_bookings, :coach_access)

    on_exit(fn ->
      Application.put_env(:sports_coach_bookings, :coach_access, previous)
    end)

    {:ok, tenant: tenant}
  end

  describe "owner/admin" do
    test "owner lists and searches players", %{conn: conn, tenant: tenant} do
      insert(:player, tenant_id: tenant.id, first_name: "Taylor", last_name: "Reed")
      insert(:player, tenant_id: tenant.id, first_name: "Jordan", last_name: "Blake")

      conn = staff_conn(conn, tenant, :owner)

      body = conn |> get("/api/staff/players") |> json_response(200)
      assert length(body["data"]) == 2

      search = conn |> get("/api/staff/players?q=taylor") |> json_response(200)
      assert [%{"first_name" => "Taylor"}] = search["data"]
    end

    test "owner reads a player without medical values", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)

      body =
        conn
        |> staff_conn(tenant, :owner)
        |> get("/api/staff/players/#{player.id}")
        |> json_response(200)

      assert body["id"] == player.id
      refute Map.has_key?(body, "allergies")
    end

    test "owner reads medical info and an audit row is written", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)

      {:ok, _} =
        SportsCoachBookings.Players.upsert_medical_info(nil, player, %{"allergies" => "Peanuts"})

      body =
        conn
        |> staff_conn(tenant, :owner)
        |> get("/api/staff/players/#{player.id}/medical")
        |> json_response(200)

      assert body["allergies"] == "Peanuts"

      assert Repo.exists?(
               from e in Event,
                 where: e.action == "player.medical.read" and e.resource_id == ^player.id
             )
    end

    test "owner updates a player", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)

      body =
        conn
        |> staff_conn(tenant, :owner)
        |> put_req_header("content-type", "application/json")
        |> patch(
          "/api/staff/players/#{player.id}",
          Jason.encode!(%{"player" => %{"preferred_name" => "Ace"}})
        )
        |> json_response(200)

      assert body["preferred_name"] == "Ace"
    end
  end

  describe "coach visibility (CoachAccess stub)" do
    test "a coach with no bookings for a player gets 403", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)
      Application.put_env(:sports_coach_bookings, :coach_access, HiddenCoachAccess)

      resp =
        conn
        |> staff_conn(tenant, :coach)
        |> get("/api/staff/players/#{player.id}")

      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end

    test "a coach whose bookings make the player visible gets 200", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)
      Application.put_env(:sports_coach_bookings, :coach_access, VisibleCoachAccess)

      resp =
        conn
        |> staff_conn(tenant, :coach)
        |> get("/api/staff/players/#{player.id}")

      assert json_response(resp, 200)["id"] == player.id
    end

    test "a coach reading visible medical info is audited", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)

      {:ok, _} =
        SportsCoachBookings.Players.upsert_medical_info(nil, player, %{"conditions" => "Asthma"})

      Application.put_env(:sports_coach_bookings, :coach_access, VisibleCoachAccess)

      body =
        conn
        |> staff_conn(tenant, :coach)
        |> get("/api/staff/players/#{player.id}/medical")
        |> json_response(200)

      assert body["conditions"] == "Asthma"

      assert Repo.exists?(
               from e in Event,
                 where: e.action == "player.medical.read" and e.resource_id == ^player.id
             )
    end

    test "a coach denied medical access writes no audit row", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)
      Application.put_env(:sports_coach_bookings, :coach_access, HiddenCoachAccess)

      resp =
        conn
        |> staff_conn(tenant, :coach)
        |> get("/api/staff/players/#{player.id}/medical")

      assert json_response(resp, 403)
      refute Repo.exists?(from e in Event, where: e.action == "player.medical.read")
    end

    test "a coach cannot list players", %{conn: conn, tenant: tenant} do
      insert(:player, tenant_id: tenant.id)

      resp = conn |> staff_conn(tenant, :coach) |> get("/api/staff/players")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "tenant isolation at the boundary" do
    test "a staff actor from another tenant cannot read a player", %{conn: conn, tenant: tenant} do
      player = insert(:player, tenant_id: tenant.id)
      other = insert(:tenant)

      resp =
        conn
        |> staff_conn(other, :owner)
        |> get("/api/staff/players/#{player.id}")

      assert json_response(resp, 404)["error"]["code"] == "not_found"
    end
  end
end
