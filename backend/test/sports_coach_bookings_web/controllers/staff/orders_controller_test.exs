defmodule SportsCoachBookingsWeb.Staff.OrdersControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.ObanHelpers

  setup do
    tenant = insert(:tenant, slug: "staff-orders-#{System.unique_integer([:positive])}")
    SportsCoachBookings.DataCase.put_tenant(tenant)
    insert(:provider_account, charges_enabled: true)
    %{tenant: tenant}
  end

  defp seed_variant(stock \\ 5) do
    {:ok, product} = Inventory.create_product(nil, %{"name" => "Jersey", "taxable" => false})

    {:ok, variant} =
      Inventory.create_variant(nil, product.id, %{
        "sku" => "SKU-#{System.unique_integer([:positive])}",
        "price" => 2_500,
        "option_values" => %{"size" => "YM"}
      })

    {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => stock})
    variant
  end

  test "creates an offline order", %{conn: conn, tenant: tenant} do
    household = Ecto.UUID.generate()
    variant = seed_variant()

    body =
      conn
      |> staff_conn(tenant, :admin)
      |> post("/api/staff/orders", %{
        "order" => %{
          "household_id" => household,
          "lines" => [%{"type" => "product", "ref_id" => variant.id, "quantity" => 1}]
        }
      })
      |> json_response(201)

    assert body["status"] == "paid"
    assert body["payment_method"] == "offline"
    assert body["total"] == 2_500

    _ = ObanHelpers.drain_all()
    assert Enum.any?(body["lines"], &(&1["ref_id"] == variant.id))
  end

  test "lists and shows orders", %{conn: conn, tenant: tenant} do
    household = Ecto.UUID.generate()
    variant = seed_variant()

    {:ok, order} =
      Commerce.create_offline_order(nil, %{
        household_id: household,
        lines: [%{type: :product, ref_id: variant.id, quantity: 1}]
      })

    list =
      conn
      |> staff_conn(tenant, :owner)
      |> get("/api/staff/orders", %{"household_id" => household})
      |> json_response(200)

    assert [%{"id" => id}] = list["data"]
    assert id == order.id

    detail =
      conn
      |> staff_conn(tenant, :owner)
      |> get("/api/staff/orders/#{order.id}")
      |> json_response(200)

    assert detail["id"] == order.id
    assert length(detail["lines"]) == 1
  end

  test "refunds a line of a paid order", %{conn: conn, tenant: tenant} do
    household = Ecto.UUID.generate()
    variant = seed_variant()

    {:ok, order} =
      Commerce.create_offline_order(nil, %{
        household_id: household,
        lines: [%{type: :product, ref_id: variant.id, quantity: 1}]
      })

    line = hd(order.lines)

    body =
      conn
      |> staff_conn(tenant, :owner)
      |> post("/api/staff/orders/#{order.id}/refund", %{
        "order_line_id" => line.id,
        "reason" => "damaged"
      })
      |> json_response(200)

    assert [%{"status" => "refunded", "payment_refunded" => false}] = body["refunds"]
    assert Commerce.get_order!(order.id).status == :refunded
    assert ObanHelpers.event_count("order.refunded") == 1
  end

  test "a coach may not refund or create offline orders", %{conn: conn, tenant: tenant} do
    household = Ecto.UUID.generate()
    variant = seed_variant()

    {:ok, order} =
      Commerce.create_offline_order(nil, %{
        household_id: household,
        lines: [%{type: :product, ref_id: variant.id, quantity: 1}]
      })

    coach = staff_conn(conn, tenant, :coach)

    assert json_response(get(coach, "/api/staff/orders"), 200)

    refund =
      post(coach, "/api/staff/orders/#{order.id}/refund", %{"order_line_id" => hd(order.lines).id})

    assert json_response(refund, 403)["error"]["code"] == "forbidden"

    create =
      post(coach, "/api/staff/orders", %{
        "order" => %{"household_id" => household, "lines" => []}
      })

    assert json_response(create, 403)["error"]["code"] == "forbidden"
  end

  test "anonymous callers are forbidden", %{conn: conn, tenant: tenant} do
    resp = conn |> with_host(tenant.slug) |> get("/api/staff/orders")
    assert json_response(resp, 403)
  end
end
