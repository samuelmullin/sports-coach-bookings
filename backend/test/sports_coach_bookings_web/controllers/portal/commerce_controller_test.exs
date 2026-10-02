defmodule SportsCoachBookingsWeb.Portal.CommerceControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.ObanHelpers

  setup do
    tenant = insert(:tenant, slug: "portal-commerce-#{System.unique_integer([:positive])}")
    SportsCoachBookings.DataCase.put_tenant(tenant)
    insert(:provider_account, charges_enabled: true)
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

  defp seed_product(stock) do
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

  test "shows an empty cart for a new household", %{conn: conn, tenant: tenant} do
    household = insert(:household).id

    body =
      conn
      |> customer(tenant, household)
      |> get("/api/portal/cart")
      |> json_response(200)

    assert body["household_id"] == household
    assert body["lines"] == []
  end

  test "adds a line, prices it, and checks out", %{conn: conn, tenant: tenant} do
    household = insert(:household).id
    variant = seed_product(4)
    conn = customer(conn, tenant, household)

    created =
      conn
      |> post("/api/portal/cart/lines", %{
        "line" => %{"type" => "product", "ref_id" => variant.id, "quantity" => 2}
      })
      |> json_response(201)

    assert [%{"type" => "product", "quantity" => 2}] = created["lines"]

    price = conn |> get("/api/portal/cart/price") |> json_response(200)
    assert price["total"] == 5_000
    assert length(price["lines"]) == 1

    checkout = conn |> post("/api/portal/checkout") |> json_response(201)
    assert checkout["redirect_url"] =~ "provider.fake"
    assert checkout["order"]["status"] == "pending_payment"
    assert checkout["order"]["total"] == 5_000

    # The cart is cleared after a successful checkout.
    assert conn |> get("/api/portal/cart") |> json_response(200) |> Map.get("lines") == []
  end

  test "order history shows the household's paid orders", %{conn: conn, tenant: tenant} do
    household = insert(:household).id
    variant = seed_product(3)

    {:ok, order} =
      Commerce.create_offline_order(
        nil,
        %{household_id: household, lines: [%{type: :product, ref_id: variant.id, quantity: 1}]}
      )

    _ = ObanHelpers.drain_all()
    conn = customer(conn, tenant, household)

    history = conn |> get("/api/portal/orders") |> json_response(200)
    assert [%{"id" => id, "number" => number}] = history["data"]
    assert id == order.id
    assert number =~ "A-"

    detail = conn |> get("/api/portal/orders/#{order.id}") |> json_response(200)
    assert detail["id"] == order.id
    assert [%{"type" => "product"}] = detail["lines"]
  end

  test "a household cannot read another household's order", %{conn: conn, tenant: tenant} do
    other = Ecto.UUID.generate()
    variant = seed_product(3)

    {:ok, order} =
      Commerce.create_offline_order(
        nil,
        %{household_id: other, lines: [%{type: :product, ref_id: variant.id, quantity: 1}]}
      )

    resp =
      conn
      |> customer(tenant, Ecto.UUID.generate())
      |> get("/api/portal/orders/#{order.id}")

    assert json_response(resp, 404)
  end

  test "anonymous callers are forbidden", %{conn: conn, tenant: tenant} do
    resp = conn |> with_host(tenant.slug) |> get("/api/portal/cart")
    assert json_response(resp, 403)["error"]["code"] == "forbidden"
  end

  test "a bad discount code surfaces at checkout", %{conn: conn, tenant: tenant} do
    household = insert(:household).id
    variant = seed_product(2)

    {:ok, package} =
      Catalog.create_package(nil, %{name: "Pack", credit_quantity: 3, price: 5_000})

    _ = package
    conn = customer(conn, tenant, household)

    _ =
      conn
      |> post("/api/portal/cart/lines", %{
        "line" => %{"type" => "product", "ref_id" => variant.id, "quantity" => 1}
      })

    _ = conn |> post("/api/portal/cart/discount", %{"code" => "NOPE"})

    resp = conn |> post("/api/portal/checkout")
    assert json_response(resp, 422)["error"]["code"] == "invalid_code"
  end
end
