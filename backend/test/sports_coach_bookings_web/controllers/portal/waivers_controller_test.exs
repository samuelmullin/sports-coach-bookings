defmodule SportsCoachBookingsWeb.Portal.WaiversControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Waivers

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    household = insert(:household).id
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

  defp published_waiver(attrs \\ %{}) do
    attrs = Map.merge(%{"name" => "General", "scope" => "all_bookings"}, attrs)
    {:ok, template} = Waivers.create_template(nil, attrs)
    {:ok, draft} = Waivers.create_version(nil, template.id, %{"body_markdown" => "Sign me"})
    {:ok, published} = Waivers.publish_version(nil, draft.id)
    {template, published}
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  describe "player waivers" do
    test "lists required and signed waivers for a player", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      {_template, published} = published_waiver()
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      body =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/players/#{player.id}/waivers")
        |> json_response(200)

      assert body["player_id"] == player.id
      assert [%{"signed" => false, "version_id" => vid}] = body["waivers"]
      assert vid == published.id
    end

    test "another household's manager cannot read a player's waivers", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      resp =
        conn
        |> customer(tenant, Ecto.UUID.generate())
        |> get("/api/portal/players/#{player.id}/waivers")

      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "version body" do
    test "returns a published version body", %{conn: conn, tenant: tenant, household: household} do
      {_template, published} = published_waiver()

      body =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/waivers/versions/#{published.id}")
        |> json_response(200)

      assert body["body_markdown"] == "Sign me"
      assert body["content_sha256"] == published.content_sha256
    end

    test "a draft version body is not visible in the portal", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      {:ok, template} =
        Waivers.create_template(nil, %{"name" => "Draft", "scope" => "all_bookings"})

      {:ok, draft} = Waivers.create_version(nil, template.id, %{"body_markdown" => "Draft"})

      resp =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/waivers/versions/#{draft.id}")

      assert json_response(resp, 404)["error"]["code"] == "not_found"
    end
  end

  describe "signing" do
    test "signs the current published version", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      {_template, published} = published_waiver()
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      body =
        conn
        |> customer(tenant, household)
        |> json_post("/api/portal/players/#{player.id}/waivers/#{published.id}/sign", %{
          "signature" => %{
            "content_sha256" => published.content_sha256,
            "signer_name_typed" => "Dana Reyes",
            "signer_relationship" => "Parent",
            "consent_checkbox" => true
          }
        })
        |> json_response(201)

      assert body["player_id"] == player.id
      assert body["content_sha256"] == published.content_sha256
      assert body["ip"] == "127.0.0.1"
    end

    test "rejects a stale content_sha256", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      {_template, published} = published_waiver()
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      resp =
        conn
        |> customer(tenant, household)
        |> json_post("/api/portal/players/#{player.id}/waivers/#{published.id}/sign", %{
          "signature" => %{
            "content_sha256" => Waivers.hash_body("stale"),
            "signer_name_typed" => "Dana Reyes",
            "consent_checkbox" => true
          }
        })

      assert json_response(resp, 422)["error"]["code"] == "stale_waiver"
    end

    test "forbids signing for another household's player", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      {_template, published} = published_waiver()
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      resp =
        conn
        |> customer(tenant, Ecto.UUID.generate())
        |> json_post("/api/portal/players/#{player.id}/waivers/#{published.id}/sign", %{
          "signature" => %{
            "content_sha256" => published.content_sha256,
            "signer_name_typed" => "Mallory",
            "consent_checkbox" => true
          }
        })

      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "pdf download" do
    test "returns PDF metadata for the signer's own signature", %{
      conn: conn,
      tenant: tenant,
      household: household
    } do
      {_template, published} = published_waiver()
      player = insert(:player, tenant_id: tenant.id, household_id: household)

      {:ok, signature} =
        Waivers.sign(nil, player.id, published.id, %{
          "content_sha256" => published.content_sha256,
          "customer_user_id" => Ecto.UUID.generate(),
          "signer_name_typed" => "Dana Reyes",
          "consent_checkbox" => true,
          "ip" => "127.0.0.1",
          "user_agent" => "ExUnit"
        })

      resp =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/waivers/signatures/#{signature.id}/pdf")

      assert resp.status == 200
      assert ["application/pdf"] = get_resp_header(resp, "content-type")
      assert [disposition] = get_resp_header(resp, "content-disposition")
      assert disposition =~ "waiver-#{signature.id}.pdf"
      assert ["private, no-store"] = get_resp_header(resp, "cache-control")
      assert "%PDF-" <> _ = resp.resp_body

      resp =
        conn
        |> customer(tenant, Ecto.UUID.generate())
        |> get("/api/portal/waivers/signatures/#{signature.id}/pdf")

      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "email a copy" do
    test "queues the waiver version body to an anonymous recipient", %{
      conn: conn,
      tenant: tenant
    } do
      {_template, published} = published_waiver()

      body =
        conn
        |> with_host(tenant.slug)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/portal/waivers/versions/#{published.id}/email",
          Jason.encode!(%{"email" => "dana@example.com"})
        )
        |> json_response(202)

      assert body == %{"status" => "queued", "email" => "dana@example.com"}

      assert [%SportsCoachBookings.Notifications.Message{template_key: "legal_document"}] =
               Repo.all(SportsCoachBookings.Notifications.Message)

      assert [%SportsCoachBookings.Notifications.Delivery{email: "dana@example.com"}] =
               Repo.all(SportsCoachBookings.Notifications.Delivery)
    end

    test "rejects an invalid email", %{conn: conn, tenant: tenant} do
      {_template, published} = published_waiver()

      resp =
        conn
        |> with_host(tenant.slug)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/portal/waivers/versions/#{published.id}/email",
          Jason.encode!(%{"email" => "nope"})
        )

      assert json_response(resp, 422)["error"]["code"] == "invalid_email"
    end
  end

  describe "authorization" do
    test "anonymous callers are denied", %{conn: conn, tenant: tenant} do
      resp = get(with_host(conn, tenant.slug), "/api/portal/waivers/status")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end
end
