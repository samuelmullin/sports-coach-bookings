defmodule SportsCoachBookingsWeb.Staff.InventoryControllerTest do
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

  describe "products" do
    test "an owner creates a product, variant, and receives stock", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)

      product =
        conn
        |> json_post("/api/staff/inventory/products", %{"name" => "Jersey"})
        |> json_response(201)

      assert product["name"] == "Jersey"

      variant =
        conn
        |> json_post("/api/staff/inventory/products/#{product["id"]}/variants", %{
          "sku" => "J-1",
          "price" => 2500,
          "low_stock_threshold" => 2,
          "option_values" => %{"size" => "YM"}
        })
        |> json_response(201)

      assert variant["sku"] == "J-1"

      movement =
        conn
        |> json_post("/api/staff/inventory/variants/#{variant["id"]}/stock/receive", %{
          "quantity" => 10
        })
        |> json_response(201)

      assert movement["kind"] == "received"
      assert movement["delta"] == 10

      adjusted =
        conn
        |> json_post("/api/staff/inventory/variants/#{variant["id"]}/stock/adjust", %{
          "delta" => -1,
          "reason" => "damaged"
        })
        |> json_response(201)

      assert adjusted["delta"] == -1

      movements =
        conn
        |> get("/api/staff/inventory/variants/#{variant["id"]}/stock/movements")
        |> json_response(200)

      assert length(movements["data"]) == 2

      levels = conn |> get("/api/staff/inventory/stock_levels") |> json_response(200)
      assert [%{"on_hand" => 9, "reserved" => 0, "available" => 9}] = levels["data"]
    end

    test "an owner reorders products", %{conn: conn, tenant: tenant} do
      a = insert(:product, tenant_id: tenant.id)
      b = insert(:product, tenant_id: tenant.id)
      conn = staff_conn(conn, tenant, :owner)

      body =
        conn
        |> json_post("/api/staff/inventory/products/reorder", %{"ids" => [b.id, a.id]})
        |> json_response(200)

      assert Enum.map(body["data"], & &1["id"]) == [b.id, a.id]
    end

    test "a coach may list but not create products", %{conn: conn, tenant: tenant} do
      insert(:product, tenant_id: tenant.id, name: "Cap")
      conn = staff_conn(conn, tenant, :coach)

      assert [%{"name" => "Cap"}] =
               (conn |> get("/api/staff/inventory/products") |> json_response(200))["data"]

      assert conn
             |> json_post("/api/staff/inventory/products", %{"name" => "Nope"})
             |> json_response(403)
    end

    test "an anonymous caller cannot list staff products", %{conn: conn, tenant: tenant} do
      resp = get(with_host(conn, tenant.slug), "/api/staff/inventory/products")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "fulfillments" do
    test "an owner moves a fulfillment from pending to picked up", %{conn: conn, tenant: tenant} do
      fulfillment = insert(:fulfillment, tenant_id: tenant.id)
      conn = staff_conn(conn, tenant, :owner)

      ready =
        conn
        |> post("/api/staff/inventory/fulfillments/#{fulfillment.id}/ready")
        |> json_response(200)

      assert ready["status"] == "ready_for_pickup"

      picked =
        conn
        |> post("/api/staff/inventory/fulfillments/#{fulfillment.id}/pickup")
        |> json_response(200)

      assert picked["status"] == "picked_up"
      assert picked["picked_up_at"]

      queue = conn |> get("/api/staff/inventory/fulfillments") |> json_response(200)
      assert [%{"id" => id}] = queue["data"]
      assert id == fulfillment.id
    end
  end

  describe "uploads" do
    test "presigns a product image upload", %{conn: conn, tenant: tenant} do
      conn = staff_conn(conn, tenant, :owner)

      body =
        conn
        |> json_post("/api/staff/inventory/uploads", %{
          "filename" => "jersey.png",
          "content_type" => "image/png",
          "byte_size" => 1234
        })
        |> json_response(201)

      assert body["key"] =~ tenant.id
      assert body["upload_url"]
    end
  end
end
