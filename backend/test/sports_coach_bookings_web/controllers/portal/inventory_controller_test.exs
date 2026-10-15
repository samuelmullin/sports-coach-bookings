defmodule SportsCoachBookingsWeb.Portal.InventoryControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Inventory

  defmodule TestOrderSource do
    @moduledoc false
    @behaviour SportsCoachBookings.Inventory.OrderSource

    @impl true
    def order_line_ids_for_household(_household_id) do
      Application.get_env(:sports_coach_bookings, :test_order_line_ids, [])
    end
  end

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)

    previous = Application.get_env(:sports_coach_bookings, :inventory_order_source)
    Application.put_env(:sports_coach_bookings, :inventory_order_source, TestOrderSource)

    on_exit(fn ->
      Application.put_env(:sports_coach_bookings, :inventory_order_source, previous)
    end)

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

  describe "shop" do
    test "lists only active, portal-visible products with availability labels", %{
      conn: conn,
      tenant: tenant
    } do
      {:ok, available} = Inventory.create_product(nil, %{"name" => "In Stock Tee"})

      {:ok, variant} =
        Inventory.create_variant(nil, available.id, %{"sku" => "T-1", "price" => 2000})

      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})

      Inventory.create_product(nil, %{"name" => "Sold Out Tee"})
      Inventory.create_product(nil, %{"name" => "Hidden", "visible_in_portal" => false})

      {:ok, archived} = Inventory.create_product(nil, %{"name" => "Archived"})
      {:ok, _} = Inventory.archive_product(nil, archived.id)

      body =
        conn
        |> with_host(tenant.slug)
        |> get("/api/portal/inventory/products")
        |> json_response(200)

      labels = Map.new(body["data"], &{&1["name"], &1["availability"]})

      assert labels["In Stock Tee"] == "in stock"
      assert labels["Sold Out Tee"] == "sold out"
      refute Map.has_key?(labels, "Hidden")
      refute Map.has_key?(labels, "Archived")

      refute inspect(body) =~ "on_hand"
    end

    test "shows a product with per-variant labels", %{conn: conn, tenant: tenant} do
      {:ok, product} = Inventory.create_product(nil, %{"name" => "Hoodie"})

      {:ok, variant} =
        Inventory.create_variant(nil, product.id, %{
          "sku" => "H-1",
          "price" => 5000,
          "low_stock_threshold" => 3
        })

      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 2})

      body =
        conn
        |> with_host(tenant.slug)
        |> get("/api/portal/inventory/products/#{product.id}")
        |> json_response(200)

      assert body["name"] == "Hoodie"
      assert body["availability"] == "low stock"
      assert [%{"availability" => "low stock", "price" => 5000}] = body["variants"]
    end
  end

  describe "pickups" do
    test "lists pickup status for the household's orders", %{conn: conn, tenant: tenant} do
      line_id = Ecto.UUID.generate()
      Application.put_env(:sports_coach_bookings, :test_order_line_ids, [line_id])

      fulfillment =
        insert(:fulfillment,
          tenant_id: tenant.id,
          order_line_id: line_id,
          status: :ready_for_pickup
        )

      household = insert(:household).id

      body =
        conn
        |> customer(tenant, household)
        |> get("/api/portal/inventory/pickups")
        |> json_response(200)

      assert [pickup] = body["data"]
      assert pickup["id"] == fulfillment.id
      assert pickup["status"] == "ready_for_pickup"
      assert pickup["product_name"]
    end

    test "an anonymous caller cannot view pickups", %{conn: conn, tenant: tenant} do
      resp = conn |> with_host(tenant.slug) |> get("/api/portal/inventory/pickups")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end
end
