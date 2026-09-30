defmodule SportsCoachBookingsWeb.Staff.WaiversControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Waivers

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
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

  describe "templates" do
    test "an owner creates, lists, and archives a template", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)

      created =
        json_post(conn, "/api/staff/waivers/templates", %{
          "template" => %{"name" => "General", "scope" => "all_bookings"}
        })

      assert %{"id" => id, "name" => "General", "scope" => "all_bookings"} =
               json_response(created, 201)

      list = conn |> get("/api/staff/waivers/templates") |> json_response(200)
      assert Enum.map(list["data"], & &1["id"]) == [id]

      archived = json_post(conn, "/api/staff/waivers/templates/#{id}/archive", %{})
      assert json_response(archived, 200)["active"] == false
    end

    test "a coach cannot create a template", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :coach)

      resp =
        json_post(conn, "/api/staff/waivers/templates", %{
          "template" => %{"name" => "Nope", "scope" => "all_bookings"}
        })

      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end

    test "an anonymous caller cannot list templates", %{conn: conn, tenant: tenant} do
      resp = get(with_host(conn, tenant.slug), "/api/staff/waivers/templates")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "versions" do
    test "an owner drafts, previews, and publishes a version", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)

      {:ok, template} =
        Waivers.create_template(nil, %{"name" => "T", "scope" => "all_bookings"})

      created =
        json_post(conn, "/api/staff/waivers/templates/#{template.id}/versions", %{
          "version" => %{"body_markdown" => "Draft body"}
        })

      assert %{"id" => version_id, "status" => "draft", "version" => 1} =
               json_response(created, 201)

      preview =
        conn
        |> get("/api/staff/waivers/versions/#{version_id}/preview")
        |> json_response(200)

      assert preview["body_markdown"] == "Draft body"

      published = json_post(conn, "/api/staff/waivers/versions/#{version_id}/publish", %{})
      assert json_response(published, 200)["status"] == "published"
    end

    test "a published body cannot be edited", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)
      {_template, published} = published_waiver_in_tenant()

      resp =
        json_patch(conn, "/api/staff/waivers/versions/#{published.id}", %{
          "version" => %{"body_markdown" => "Tampered"}
        })

      assert json_response(resp, 422)["error"]["code"] == "immutable_version"
    end
  end

  describe "signatures" do
    test "lists, exports, and returns PDF metadata", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)
      {_template, published} = published_waiver_in_tenant()
      player_id = Ecto.UUID.generate()

      {:ok, signature} =
        Waivers.sign(nil, player_id, published.id, %{
          "content_sha256" => published.content_sha256,
          "customer_user_id" => Ecto.UUID.generate(),
          "signer_name_typed" => "Dana Reyes",
          "consent_checkbox" => true,
          "ip" => "127.0.0.1",
          "user_agent" => "ExUnit"
        })

      list = conn |> get("/api/staff/waivers/signatures") |> json_response(200)
      assert [%{"id" => id}] = list["data"]
      assert id == signature.id

      csv = get(conn, "/api/staff/waivers/signatures/export")

      assert csv.status == 200
      assert csv.resp_body =~ "player_id"
      assert csv.resp_body =~ player_id

      pdf = conn |> get("/api/staff/waivers/signatures/#{signature.id}/pdf") |> json_response(200)
      assert pdf["signature_id"] == signature.id
      assert pdf["status"] == "pending"
    end
  end

  defp published_waiver_in_tenant do
    {:ok, template} =
      Waivers.create_template(nil, %{"name" => "T", "scope" => "all_bookings"})

    {:ok, draft} = Waivers.create_version(nil, template.id, %{"body_markdown" => "Body"})
    {:ok, published} = Waivers.publish_version(nil, draft.id)
    {template, published}
  end
end
