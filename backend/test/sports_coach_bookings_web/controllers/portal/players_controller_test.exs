defmodule SportsCoachBookingsWeb.Portal.PlayersControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    household = Ecto.UUID.generate()
    %{tenant: tenant, household: household}
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

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  defp json_patch(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> patch(path, Jason.encode!(payload))
  end

  defp json_put(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(payload))
  end

  describe "players" do
    test "a manager creates and lists a player in their household", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      conn = customer(conn, tenant, household)

      created =
        json_post(conn, "/api/portal/players", %{
          "player" => %{
            "first_name" => "Jamie",
            "last_name" => "Lee",
            "date_of_birth" => "2016-04-01",
            "household_id" => Ecto.UUID.generate()
          }
        })

      assert %{"id" => id, "household_id" => ^household, "first_name" => "Jamie"} =
               json_response(created, 201)

      body = conn |> get("/api/portal/players") |> json_response(200)
      assert Enum.map(body["data"], & &1["id"]) == [id]
    end

    test "lists only the caller's household", %{conn: conn, tenant: tenant, household: household} do
      insert(:player, tenant_id: tenant.id, household_id: household, first_name: "Mine")

      insert(:player,
        tenant_id: tenant.id,
        household_id: Ecto.UUID.generate(),
        first_name: "Other"
      )

      body =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/players")
        |> json_response(200)

      assert Enum.map(body["data"], & &1["first_name"]) == ["Mine"]
    end

    test "shows detail without medical values", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)
      {:ok, _} = Players.upsert_medical_info(nil, player, %{"allergies" => "Peanuts"})

      body =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/players/#{player.id}")
        |> json_response(200)

      assert body["id"] == player.id
      assert body["has_medical_info"] == true
      refute Map.has_key?(body, "allergies")
    end

    test "updates a player without allowing a household change", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      body =
        conn
        |> customer(tenant, household)
        |> json_patch("/api/portal/players/#{player.id}", %{
          "player" => %{"preferred_name" => "Ace", "household_id" => Ecto.UUID.generate()}
        })
        |> json_response(200)

      assert body["preferred_name"] == "Ace"
      assert body["household_id"] == household
    end

    test "another household's manager cannot read a player", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      resp =
        conn
        |> customer(tenant, Ecto.UUID.generate())
        |> get("/api/portal/players/#{player.id}")

      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end

    test "anonymous callers are denied", %{conn: conn, tenant: tenant} do
      resp = get(with_host(conn, tenant.slug), "/api/portal/players")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "profiles" do
    test "updates a profile and validates positions", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)
      conn = customer(conn, tenant, household)

      ok =
        conn
        |> json_put("/api/portal/players/#{player.id}/profile", %{
          "profile" => %{"preferred_positions" => ["GK", "ST"], "home_club" => "City FC"}
        })

      assert %{"preferred_positions" => ["GK", "ST"], "home_club" => "City FC"} =
               json_response(ok, 200)

      bad =
        conn
        |> json_put("/api/portal/players/#{player.id}/profile", %{
          "profile" => %{"preferred_positions" => ["QB"]}
        })

      assert json_response(bad, 422)["error"]["code"] == "validation_error"
    end
  end

  describe "contacts and pickups" do
    test "manages emergency contacts", %{conn: conn, tenant: tenant, household: household} do
      player = insert(:player, tenant_id: tenant.id, household_id: household)
      conn = customer(conn, tenant, household)

      created =
        json_post(conn, "/api/portal/players/#{player.id}/emergency_contacts", %{
          "emergency_contact" => %{"name" => "Pat", "phone" => "555", "priority" => 1}
        })

      assert %{"id" => contact_id} = json_response(created, 201)

      list =
        conn |> get("/api/portal/players/#{player.id}/emergency_contacts") |> json_response(200)

      assert [%{"id" => ^contact_id}] = list["data"]

      deleted = delete(conn, "/api/portal/players/#{player.id}/emergency_contacts/#{contact_id}")
      assert deleted.status == 204
    end

    test "manages authorized pickups and the no-restrictions flag", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)
      conn = customer(conn, tenant, household)

      created =
        json_post(conn, "/api/portal/players/#{player.id}/authorized_pickups", %{
          "authorized_pickup" => %{"name" => "Grandma"}
        })

      assert %{"id" => pickup_id} = json_response(created, 201)

      body =
        conn
        |> json_patch("/api/portal/players/#{player.id}", %{
          "player" => %{"no_pickup_restrictions" => true}
        })
        |> json_response(200)

      assert body["no_pickup_restrictions"] == true
      assert body["id"] == player.id
      assert is_binary(pickup_id)
    end
  end

  describe "medical endpoint" do
    test "a manager reads and writes medical info; every read is audited", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)
      conn = customer(conn, tenant, household)

      written =
        json_put(conn, "/api/portal/players/#{player.id}/medical", %{
          "medical_info" => %{"allergies" => "Peanuts", "notes" => "EpiPen in bag"}
        })

      assert %{"allergies" => "Peanuts", "has_medical_info" => true} = json_response(written, 200)

      read = conn |> get("/api/portal/players/#{player.id}/medical") |> json_response(200)
      assert read["allergies"] == "Peanuts"

      assert Repo.exists?(
               from e in Event,
                 where: e.action == "player.medical.read" and e.resource_id == ^player.id
             )
    end

    test "medical values never appear in the list payload", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)
      {:ok, _} = Players.upsert_medical_info(nil, player, %{"allergies" => "Peanuts"})

      body =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/players")
        |> json_response(200)

      refute Map.has_key?(hd(body["data"]), "allergies")
      refute Map.has_key?(hd(body["data"]), "medications")
    end
  end
end
