defmodule SportsCoachBookings.InventoryTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.Inventory.OrderEventsSubscriber
  alias SportsCoachBookings.Inventory.StockMovement
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp product_with_variant(attrs \\ %{}) do
    {:ok, product} = Inventory.create_product(nil, %{"name" => "Jersey"})

    {:ok, variant} =
      Inventory.create_variant(
        nil,
        product.id,
        Map.merge(%{"sku" => "J-1", "price" => 2500}, attrs)
      )

    {product, variant}
  end

  describe "products and variants" do
    test "creates a product and a variant with a zeroed stock level" do
      {product, variant} = product_with_variant(%{"low_stock_threshold" => 2})

      assert product.name == "Jersey"
      assert Inventory.fetch_stock_level(variant.id).on_hand == 0
      assert Inventory.fetch_stock_level(variant.id).reserved == 0
    end

    test "archives a product without deleting it" do
      {product, _variant} = product_with_variant()
      assert {:ok, archived} = Inventory.archive_product(nil, product.id)
      refute archived.active
    end
  end

  describe "stock ledger" do
    test "receive and adjust move on_hand and write movements" do
      {_product, variant} = product_with_variant()

      assert {:ok, received} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 10})
      assert received.kind == :received
      assert received.delta == 10

      assert {:ok, adjusted} =
               Inventory.adjust_stock(nil, variant.id, %{"delta" => -2, "reason" => "damaged"})

      assert adjusted.kind == :adjusted
      assert Inventory.fetch_stock_level(variant.id).on_hand == 8
    end

    test "adjust rejects dropping on_hand below reserved" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      {:ok, _} = Inventory.reserve(Ecto.UUID.generate(), [%{variant_id: variant.id, quantity: 4}])

      assert {:error, {:stock_below_reserved, _}} =
               Inventory.adjust_stock(nil, variant.id, %{"delta" => -2, "reason" => "oops"})
    end

    test "on_hand equals the sum of non-reservation movements" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 10})
      {:ok, _} = Inventory.adjust_stock(nil, variant.id, %{"delta" => -3, "reason" => "damaged"})
      order_id = Ecto.UUID.generate()
      {:ok, _} = Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 2}])
      {:ok, _} = Inventory.mark_order_paid(order_id, [])

      ledger =
        Repo.one(
          from m in StockMovement,
            where:
              m.variant_id == ^variant.id and m.kind in [:received, :sold, :adjusted, :returned],
            select: coalesce(sum(m.delta), 0)
        )

      assert Inventory.fetch_stock_level(variant.id).on_hand == ledger
      assert ledger == 5
    end
  end

  describe "price_and_availability/1" do
    test "returns price, available, and taxable" do
      {_product, variant} = product_with_variant(%{"sku" => "J-2", "price" => 1999})
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 4})
      {:ok, _} = Inventory.reserve(Ecto.UUID.generate(), [%{variant_id: variant.id, quantity: 1}])

      info = Inventory.price_and_availability([variant.id]) |> Map.fetch!(variant.id)
      assert info.available == 3
      assert info.taxable == true
      assert info.price.amount == 1999
      assert info.price.currency == "CAD"
    end
  end

  describe "reserve/2" do
    test "is idempotent for the same order and variant" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      order_id = Ecto.UUID.generate()

      assert {:ok, %{reservations: [_]}} =
               Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 2}])

      assert {:ok, %{reservations: []}} =
               Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 2}])

      assert Inventory.fetch_stock_level(variant.id).reserved == 2
    end

    test "returns insufficient_stock with the available count" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 1})

      assert {:error, {:insufficient_stock, _id, 1}} =
               Inventory.reserve(Ecto.UUID.generate(), [%{variant_id: variant.id, quantity: 2}])
    end

    test "is atomic across lines" do
      {_product, variant_a} = product_with_variant(%{"sku" => "A"})
      {_product, variant_b} = product_with_variant(%{"sku" => "B"})
      {:ok, _} = Inventory.receive_stock(nil, variant_a.id, %{"quantity" => 10})
      {:ok, _} = Inventory.receive_stock(nil, variant_b.id, %{"quantity" => 1})

      assert {:error, {:insufficient_stock, _, _}} =
               Inventory.reserve(Ecto.UUID.generate(), [
                 %{variant_id: variant_a.id, quantity: 2},
                 %{variant_id: variant_b.id, quantity: 2}
               ])

      assert Inventory.fetch_stock_level(variant_a.id).reserved == 0
    end

    test "20 concurrent reservations for 5 units: exactly 5 succeed" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      tenant = TenantContext.get_tenant()

      results =
        1..20
        |> Task.async_stream(
          fn _ ->
            TenantContext.with_tenant(tenant, fn ->
              Inventory.reserve(Ecto.UUID.generate(), [
                %{variant_id: variant.id, quantity: 1}
              ])
            end)
          end,
          max_concurrency: 20,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, {:insufficient_stock, _, _}}, &1))

      assert successes == 5, "expected exactly 5 reservations to succeed, got #{successes}"
      assert failures == 15
      assert Inventory.fetch_stock_level(variant.id).reserved == 5
    end
  end

  describe "order lifecycle" do
    test "release_order releases reservations and is idempotent" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      order_id = Ecto.UUID.generate()
      {:ok, _} = Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 3}])

      assert {:ok, [%StockMovement{kind: :released}]} = Inventory.release_order(order_id)
      assert Inventory.fetch_stock_level(variant.id).reserved == 0

      assert {:ok, []} = Inventory.release_order(order_id)
      assert Inventory.fetch_stock_level(variant.id).reserved == 0
    end

    test "order.expired subscriber releases the reservation" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      order_id = Ecto.UUID.generate()
      {:ok, _} = Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 3}])

      assert :ok = OrderEventsSubscriber.handle_event("order.expired", %{"order_id" => order_id})
      assert Inventory.fetch_stock_level(variant.id).reserved == 0

      assert :ok = OrderEventsSubscriber.handle_event("order.expired", %{"order_id" => order_id})
      assert Inventory.fetch_stock_level(variant.id).reserved == 0
    end

    test "order.cancelled releases the reservation too" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      order_id = Ecto.UUID.generate()
      {:ok, _} = Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 2}])

      assert :ok =
               OrderEventsSubscriber.handle_event("order.cancelled", %{"order_id" => order_id})

      assert Inventory.fetch_stock_level(variant.id).reserved == 0
    end

    test "reconcile_on_hand/1 confirms the ledger matches" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 7})
      assert {:ok, 7} = Inventory.reconcile_on_hand(variant.id)
    end

    test "order.paid converts to sold, creates fulfillments, and emits stock.low once" do
      {_product, variant} =
        product_with_variant(%{"sku" => "LOW", "low_stock_threshold" => 2})

      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      order_id = Ecto.UUID.generate()
      line_id = Ecto.UUID.generate()
      {:ok, _} = Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 3}])

      payload = %{
        "order_id" => order_id,
        "tenant_id" => TenantContext.get_tenant_id(),
        "lines" => [
          %{"order_line_id" => line_id, "variant_id" => variant.id, "quantity" => 3}
        ]
      }

      assert :ok = OrderEventsSubscriber.handle_event("order.paid", payload)

      level = Inventory.fetch_stock_level(variant.id)
      assert level.on_hand == 2
      assert level.reserved == 0
      assert [%{status: :pending}] = Inventory.list_fulfillments(%{"order_line_id" => line_id})

      assert low_stock_count() == 1

      # Replaying the event is idempotent: no double-sell, no duplicate
      # fulfillment, no second same-day alert.
      assert :ok = OrderEventsSubscriber.handle_event("order.paid", payload)
      assert Inventory.fetch_stock_level(variant.id).on_hand == 2
      assert length(Inventory.list_fulfillments(%{"order_line_id" => line_id})) == 1
      assert low_stock_count() == 1
    end

    test "order.refunded does not restock automatically; restock_refund does" do
      {_product, variant} = product_with_variant()
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => 5})
      order_id = Ecto.UUID.generate()
      {:ok, _} = Inventory.reserve(order_id, [%{variant_id: variant.id, quantity: 2}])
      {:ok, _} = Inventory.mark_order_paid(order_id, [])

      assert :ok = OrderEventsSubscriber.handle_event("order.refunded", %{"order_id" => order_id})
      assert Inventory.fetch_stock_level(variant.id).on_hand == 3

      assert {:ok, [%StockMovement{kind: :returned}]} =
               Inventory.restock_refund(nil, order_id, [%{variant_id: variant.id, quantity: 2}])

      assert Inventory.fetch_stock_level(variant.id).on_hand == 5

      # Idempotent.
      assert {:ok, []} =
               Inventory.restock_refund(nil, order_id, [%{variant_id: variant.id, quantity: 2}])

      assert Inventory.fetch_stock_level(variant.id).on_hand == 5
    end
  end

  describe "fulfillments" do
    test "move from pending to ready to picked up" do
      fulfillment = insert(:fulfillment, tenant_id: TenantContext.get_tenant_id())

      assert {:ok, ready} =
               Inventory.mark_ready(nil, fulfillment.id)

      assert ready.status == :ready_for_pickup

      assert {:ok, picked} = Inventory.mark_picked_up(nil, fulfillment.id)
      assert picked.status == :picked_up
      assert picked.picked_up_at
    end

    test "mark_ready and mark_picked_up are idempotent" do
      fulfillment = insert(:fulfillment, tenant_id: TenantContext.get_tenant_id())
      {:ok, _} = Inventory.mark_ready(nil, fulfillment.id)
      {:ok, picked} = Inventory.mark_picked_up(nil, fulfillment.id)

      assert {:ok, ^picked} = Inventory.mark_picked_up(nil, fulfillment.id)
    end
  end

  describe "portal availability labels" do
    test "labels sold out, low stock, and in stock without counts" do
      {product, low} = product_with_variant(%{"sku" => "LOW", "low_stock_threshold" => 2})
      {:ok, _} = Inventory.receive_stock(nil, low.id, %{"quantity" => 2})

      assert Inventory.product_availability_label(product.id) == "low stock"

      {:ok, out} = Inventory.create_variant(nil, product.id, %{"sku" => "OUT", "price" => 100})
      assert Inventory.availability_label(out, Inventory.fetch_stock_level(out.id)) == "sold out"

      {:ok, _} = Inventory.receive_stock(nil, out.id, %{"quantity" => 9})
      assert Inventory.availability_label(out, Inventory.fetch_stock_level(out.id)) == "in stock"
    end
  end

  describe "tenant isolation" do
    test "a raw SQL query cannot see another tenant's product" do
      {product, _variant} = product_with_variant()
      other = insert(:tenant)
      put_tenant(other)

      assert is_nil(Repo.get(SportsCoachBookings.Inventory.Product, product.id))
      assert SportsCoachBookings.TenantIsolation.raw_count("products", product.id) == 0
    end
  end

  defp low_stock_count do
    Repo.one(
      from j in Oban.Job,
        where: j.args["name"] == "stock.low",
        select: count(j.id)
    )
  end
end
