defmodule SportsCoachBookingsWeb.Staff.CatalogControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

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

  describe "venues" do
    test "an owner creates and reads a venue", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)

      created = json_post(conn, "/api/staff/catalog/venues", %{"name" => "Main Field"})
      assert %{"id" => id, "name" => "Main Field"} = json_response(created, 201)

      shown = get(conn, "/api/staff/catalog/venues/#{id}")
      assert json_response(shown, 200)["id"] == id
    end

    test "a coach cannot create a venue", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :coach)
      resp = json_post(conn, "/api/staff/catalog/venues", %{"name" => "Nope"})
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end

    test "an anonymous caller cannot list staff venues", %{conn: conn, tenant: tenant} do
      resp = get(with_host(conn, tenant.slug), "/api/staff/catalog/venues")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "offerings" do
    test "a coach can read offerings", %{conn: conn, tenant: tenant} do
      insert(:offering, tenant_id: tenant.id, name: "Group A")
      conn = staff_conn(conn, tenant, :coach)

      resp = get(conn, "/api/staff/catalog/offerings")
      body = json_response(resp, 200)
      assert [%{"name" => "Group A"}] = body["data"]
    end

    test "an owner can reorder offerings", %{conn: conn, tenant: tenant} do
      a = insert(:offering, tenant_id: tenant.id)
      b = insert(:offering, tenant_id: tenant.id)
      conn = staff_conn(conn, tenant, :owner)

      resp = json_post(conn, "/api/staff/catalog/offerings/reorder", %{"ids" => [b.id, a.id]})
      body = json_response(resp, 200)
      assert Enum.map(body["data"], & &1["id"]) == [b.id, a.id]
    end
  end

  describe "packages" do
    test "serialises eligible offering ids in the list and on show", %{conn: conn, tenant: tenant} do
      offering = insert(:offering, tenant_id: tenant.id, name: "Group A")
      package = insert(:package, tenant_id: tenant.id, name: "Scoped")

      insert(:package_offering,
        tenant_id: tenant.id,
        package_id: package.id,
        offering_id: offering.id
      )

      conn = staff_conn(conn, tenant, :owner)

      list = json_response(get(conn, "/api/staff/catalog/packages"), 200)
      assert [%{"offering_ids" => [offering_id]}] = list["data"]
      assert offering_id == offering.id

      show = json_response(get(conn, "/api/staff/catalog/packages/#{package.id}"), 200)
      assert show["offering_ids"] == [offering.id]
    end
  end

  describe "tax rates" do
    test "an owner creates a tax rate", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)

      resp =
        json_post(conn, "/api/staff/catalog/tax_rates", %{"name" => "HST", "rate_bps" => 1300})

      assert json_response(resp, 201)["rate_bps"] == 1300
    end
  end

  describe "discount validation" do
    test "an owner previews pricing", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)

      payload = %{
        "lines" => [
          %{
            "type" => "package",
            "ref_id" => Ecto.UUID.generate(),
            "unit_price" => 1000,
            "quantity" => 2
          }
        ]
      }

      body =
        conn |> json_post("/api/staff/catalog/discounts/validate", payload) |> json_response(200)

      assert body["subtotal"] == 2000
      assert body["total"] == 2000
    end
  end
end
