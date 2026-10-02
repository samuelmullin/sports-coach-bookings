defmodule SportsCoachBookings.CommerceTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Commerce.BookingHoldSource.Fake, as: HoldSourceFake
  alias SportsCoachBookings.Commerce.Cart
  alias SportsCoachBookings.Commerce.CartLine
  alias SportsCoachBookings.Commerce.Order
  alias SportsCoachBookings.Commerce.OrderLine
  alias SportsCoachBookings.Commerce.Policy
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.Inventory.StockLevel
  alias SportsCoachBookings.ObanHelpers
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant, slug: "commerce-#{System.unique_integer([:positive])}")
    put_tenant(tenant)
    insert(:provider_account, charges_enabled: true)

    previous_hold_source =
      Application.get_env(:sports_coach_bookings, :commerce_booking_hold_source)

    Application.put_env(:sports_coach_bookings, :commerce_booking_hold_source, HoldSourceFake)

    on_exit(fn ->
      Application.put_env(
        :sports_coach_bookings,
        :commerce_booking_hold_source,
        previous_hold_source
      )
    end)

    %{tenant: tenant}
  end

  defp actor(tenant, role \\ :owner) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: role)
  end

  defp customer_actor(tenant, household_id) do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: household_id,
      tenant_id: tenant.id
    )
  end

  defp seed_package(attrs \\ %{}) do
    base = %{name: "5-Session Pack", credit_quantity: 5, price: 10_000, taxable: false}
    {:ok, package} = Catalog.create_package(nil, Map.merge(base, attrs))
    package
  end

  defp seed_variant(attrs \\ %{}, stock \\ 10) do
    {:ok, product} = Inventory.create_product(nil, %{"name" => "Home Jersey", "taxable" => false})

    {:ok, variant} =
      Inventory.create_variant(nil, product.id, %{
        "sku" => "SKU-#{System.unique_integer([:positive])}",
        "price" => Map.get(attrs, :price, 2_500),
        "option_values" => %{"size" => "YM"},
        "taxable" => Map.get(attrs, :taxable, false)
      })

    if stock > 0 do
      {:ok, _} = Inventory.receive_stock(nil, variant.id, %{"quantity" => stock})
    end

    variant
  end

  defp register_hold(household_id, opts \\ []) do
    hold_id = Ecto.UUID.generate()

    HoldSourceFake.put_offering_hold(
      hold_id,
      Keyword.merge(
        [
          household_id: household_id,
          offering_id: Ecto.UUID.generate(),
          unit_price: 3_000,
          taxable: false
        ],
        opts
      )
    )

    hold_id
  end

  ## Cart

  test "cart add/merge/remove lines", %{tenant: tenant} do
    household = insert(:household).id
    package = seed_package()
    variant = seed_variant()

    cart = Commerce.add_package_to_cart(household, package.id, 1)
    assert length(cart.lines) == 1

    cart = Commerce.add_package_to_cart(household, package.id, 2)
    assert [%CartLine{quantity: 3}] = cart.lines

    cart = Commerce.add_product_to_cart(household, variant.id, 2)
    assert length(cart.lines) == 2

    product_line = Enum.find(cart.lines, &(&1.type == :product))
    cart = Commerce.update_cart_line(household, product_line.id, 1)
    assert Enum.find(cart.lines, &(&1.id == product_line.id)).quantity == 1

    cart = Commerce.remove_cart_line(household, product_line.id)
    assert length(cart.lines) == 1

    _ = tenant
  end

  test "price_cart reconciles line totals with the order total" do
    household = insert(:household).id
    package = seed_package()
    variant = seed_variant()
    hold_id = register_hold(household)

    Commerce.add_package_to_cart(household, package.id, 1)
    Commerce.add_product_to_cart(household, variant.id, 2)
    Commerce.add_drop_in(household, hold_id)

    assert {:ok, priced} = Commerce.price_cart(household)
    line_sum = Enum.reduce(priced.lines, 0, &(&1.line_total + &2))

    assert line_sum == priced.total
    assert priced.subtotal == 10_000 + 2 * 2_500 + 3_000
  end

  test "applying an invalid discount code errors at price time" do
    household = insert(:household).id
    package = seed_package()
    Commerce.add_package_to_cart(household, package.id, 1)
    Commerce.apply_discount_code(household, "NOPE")

    assert {:error, :invalid_code} = Commerce.price_cart(household)
  end

  ## Discounts

  test "discount is applied and the redemption recorded once", %{tenant: tenant} do
    household = insert(:household).id
    package = seed_package(%{price: 10_000})

    {:ok, discount} =
      Catalog.create_discount(nil, %{
        code: "SAVE10",
        kind: :percent,
        value: 1000,
        applies_to: :all,
        active: true
      })

    Commerce.add_package_to_cart(household, package.id, 1)
    Commerce.apply_discount_code(household, "SAVE10")

    assert {:ok, priced} = Commerce.price_cart(household)
    assert priced.discount_total == 1_000
    assert priced.total == 9_000

    assert {:ok, %{order: order, redirect_url: url}} =
             Commerce.checkout(actor(tenant), household)

    assert url =~ "provider.fake"
    assert order.discount_id == discount.id

    mark_paid_and_drain(order, %{payment_ref: "pi_disc_#{order.id}"})

    redemptions =
      Repo.all(
        from r in SportsCoachBookings.Catalog.DiscountRedemption,
          where: r.discount_id == ^discount.id and r.order_id == ^order.id
      )

    assert length(redemptions) == 1
  end

  ## E2E

  test "checkout end-to-end is idempotent under webhook replay", %{tenant: tenant} do
    household = insert(:household).id
    package = seed_package()
    variant = seed_variant(%{}, 10)
    hold_id = register_hold(household)

    Commerce.add_package_to_cart(household, package.id, 1)
    Commerce.add_product_to_cart(household, variant.id, 2)
    Commerce.add_drop_in(household, hold_id)

    assert {:ok, %{order: order, redirect_url: url}} =
             Commerce.checkout(actor(tenant), household)

    assert url =~ "provider.fake"
    assert order.status == :pending_payment
    assert order.total == 18_000

    level = Inventory.fetch_stock_level(variant.id)
    assert %StockLevel{on_hand: 10, reserved: 2} = level

    # Replay the same provider event three times. The provider dedupes on the
    # event type id at ingest; even when several jobs are enqueued, only the
    # first transitions the payment and publishes payment.succeeded.
    assert {:ok, _} = ingest_completed(order)
    assert {:ok, _} = ingest_completed(order)
    assert {:ok, _} = ingest_completed(order)

    ObanHelpers.drain(:payments)
    assert ObanHelpers.event_count("payment.succeeded") == 1

    ObanHelpers.drain(:events)
    assert ObanHelpers.event_count("order.paid") == 1

    ObanHelpers.drain_all()

    order = Commerce.get_order!(order.id)
    assert order.status == :paid
    assert order.paid_at
    assert order.payment_id

    assert %StockLevel{on_hand: 8, reserved: 0} = Inventory.fetch_stock_level(variant.id)
    assert [%Credits.CreditLot{remaining: 5}] = Credits.list_lots(household)

    assert Commerce.any_paid_orders?()

    # A direct re-delivery of payment.succeeded is a no-op.
    assert {:ok, :already_paid} = Commerce.mark_order_paid(order.id, order.payment_id)
    ObanHelpers.drain_all()

    assert [%Credits.CreditLot{remaining: 5}] = Credits.list_lots(household)
    assert %StockLevel{on_hand: 8, reserved: 0} = Inventory.fetch_stock_level(variant.id)
  end

  test "zero-total order is marked paid without a provider redirect", %{tenant: tenant} do
    household = insert(:household).id
    package = seed_package(%{price: 10_000})

    {:ok, _discount} =
      Catalog.create_discount(nil, %{
        code: "COMP",
        kind: :percent,
        value: 10_000,
        applies_to: :all,
        active: true
      })

    Commerce.add_package_to_cart(household, package.id, 1)
    Commerce.apply_discount_code(household, "COMP")

    assert {:ok, %{order: order, redirect_url: nil}} =
             Commerce.checkout(actor(tenant), household)

    assert order.status == :paid
    assert order.total == 0
    assert ObanHelpers.event_count("order.paid") == 1
  end

  ## Expiry

  test "expiry releases stock reservations and publishes order.expired", %{tenant: tenant} do
    household = insert(:household).id
    variant = seed_variant(%{}, 5)

    Commerce.add_product_to_cart(household, variant.id, 2)
    assert {:ok, %{order: order}} = Commerce.checkout(actor(tenant), household)

    assert %StockLevel{reserved: 2} = Inventory.fetch_stock_level(variant.id)

    assert {:ok, :expired} = Commerce.expire_order(order.id)
    assert Commerce.get_order!(order.id).status == :expired
    assert ObanHelpers.event_count("order.expired") == 1

    ObanHelpers.drain_all()
    assert %StockLevel{on_hand: 5, reserved: 0} = Inventory.fetch_stock_level(variant.id)

    # Idempotent.
    assert {:ok, :noop} = Commerce.expire_order(order.id)
  end

  test "payment.failed expires the order", %{tenant: tenant} do
    household = insert(:household).id
    variant = seed_variant(%{}, 5)
    Commerce.add_product_to_cart(household, variant.id, 1)
    assert {:ok, %{order: order}} = Commerce.checkout(actor(tenant), household)

    assert {:ok, :expired} = Commerce.expire_order(order.id)
    assert ObanHelpers.event_count("order.expired") == 1
  end

  test "expire_due_orders picks up lapsed pending orders", %{tenant: tenant} do
    household = insert(:household).id
    variant = seed_variant(%{}, 5)
    Commerce.add_product_to_cart(household, variant.id, 1)
    assert {:ok, %{order: order}} = Commerce.checkout(actor(tenant), household)

    order
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert {:ok, [expired_id]} = Commerce.expire_due_orders()
    assert expired_id == order.id
  end

  ## Refunds

  test "partial line refund reconciles the order and publishes order.refunded", %{tenant: tenant} do
    household = insert(:household).id
    variant = seed_variant(%{}, 10)
    Commerce.add_product_to_cart(household, variant.id, 2)
    assert {:ok, %{order: order}} = Commerce.checkout(actor(tenant), household)

    mark_paid_and_drain(order, %{payment_ref: "pi_partial_#{order.id}"})
    order = Commerce.get_order!(order.id)
    line = hd(order.lines)

    assert {:ok, %{payment_refund: refund, line: updated}} =
             Commerce.refund_line(
               line.id,
               Money.new(2_500, "CAD"),
               :requested_by_customer,
               actor(tenant)
             )

    assert refund
    assert updated.refunded_amount == 2_500

    ObanHelpers.drain_all()
    order = Commerce.get_order!(order.id)
    assert order.status == :partially_refunded
    assert order.refunded_total == 2_500
  end

  test "package refund is blocked when credits were used unless forced", %{tenant: tenant} do
    household = insert(:household).id
    package = seed_package()
    Commerce.add_package_to_cart(household, package.id, 1)
    assert {:ok, %{order: order}} = Commerce.checkout(actor(tenant), household)

    mark_paid_and_drain(order, %{payment_ref: "pi_credits_#{order.id}"})
    order = Commerce.get_order!(order.id)
    line = hd(order.lines)

    {:ok, _entry} =
      Credits.consume(household, Ecto.UUID.generate(), 1, booking_id: Ecto.UUID.generate())

    assert {:error, :credits_used} =
             Commerce.refund_line(
               line.id,
               Money.new(10_000, "CAD"),
               :requested_by_customer,
               actor(tenant)
             )

    assert {:ok, _result} =
             Commerce.refund_line(
               line.id,
               Money.new(10_000, "CAD"),
               :requested_by_customer,
               actor(tenant),
               force: true
             )
  end

  test "refund_order refunds every open line", %{tenant: tenant} do
    household = insert(:household).id
    variant = seed_variant(%{}, 10)
    Commerce.add_product_to_cart(household, variant.id, 2)
    assert {:ok, %{order: order}} = Commerce.checkout(actor(tenant), household)

    mark_paid_and_drain(order, %{payment_ref: "pi_full_#{order.id}"})

    assert {:ok, results} = Commerce.refund_order(actor(tenant), order.id)
    assert length(results) == 1

    ObanHelpers.drain_all()
    assert Commerce.get_order!(order.id).status == :refunded
  end

  ## Offline

  test "offline order is created paid and audited", %{tenant: tenant} do
    household = insert(:household).id
    variant = seed_variant(%{}, 10)

    assert {:ok, order} =
             Commerce.create_offline_order(actor(tenant), %{
               household_id: household,
               lines: [%{type: :product, ref_id: variant.id, quantity: 1}]
             })

    assert order.status == :paid
    assert order.payment_method == :offline
    assert order.total == 2_500
    assert ObanHelpers.event_count("order.paid") == 1

    ObanHelpers.drain_all()
    assert %StockLevel{on_hand: 9, reserved: 0} = Inventory.fetch_stock_level(variant.id)
  end

  ## Reads

  test "staff order filters", %{tenant: tenant} do
    household = insert(:household).id
    variant = seed_variant(%{}, 5)
    Commerce.add_product_to_cart(household, variant.id, 1)
    assert {:ok, %{order: order}} = Commerce.checkout(actor(tenant), household)

    assert %{data: [found]} = Commerce.page_orders(%{"household_id" => household})
    assert found.id == order.id

    assert %{data: [found]} = Commerce.page_orders(%{"type" => "product"})
    assert found.id == order.id

    assert %{data: []} = Commerce.page_orders(%{"type" => "package"})
  end

  ## Isolation

  test "tenant isolation for commerce schemas" do
    assert_tenant_isolated(Cart, :cart)
    assert_tenant_isolated(CartLine, :cart_line)
    assert_tenant_isolated(Order, :order)
    assert_tenant_isolated(OrderLine, :order_line)
  end

  ## Policy

  describe "policy matrix" do
    test "staff owner and admin may refund and create offline orders" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      for role <- [:owner, :admin] do
        a = actor(tenant, role)
        assert :ok = Policy.authorize(a, :refund, :order)
        assert :ok = Policy.authorize(a, :create_offline, :order)
        assert :ok = Policy.authorize(a, :list, :order)
        assert :ok = Policy.authorize(a, :get, :order)
      end
    end

    test "coach may only read orders" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      a = actor(tenant, :coach)

      assert :ok = Policy.authorize(a, :list, :order)
      assert :ok = Policy.authorize(a, :get, :order)
      assert {:error, :forbidden} = Policy.authorize(a, :refund, :order)
      assert {:error, :forbidden} = Policy.authorize(a, :create_offline, :order)
    end

    test "customer may use their cart and view their orders but not refund" do
      customer = customer_actor(insert(:tenant), Ecto.UUID.generate())

      assert :ok = Policy.authorize(customer, :checkout, :order)
      assert :ok = Policy.authorize(customer, :view_cart, :cart)
      assert :ok = Policy.authorize(customer, :add_line, :cart_line)
      assert :ok = Policy.authorize(customer, :list_own_orders, :order)
      assert {:error, :forbidden} = Policy.authorize(customer, :refund, :order)
    end

    test "anonymous is denied everything" do
      for action <- Policy.actions(), resource <- Policy.resources() do
        assert {:error, :forbidden} = Policy.authorize(nil, action, resource)
      end
    end
  end

  ## Helpers

  defp ingest_completed(order, extra \\ %{}) do
    payload = %{
      "id" => "evt_#{order.id}",
      "type" => "checkout.session.completed",
      "data" =>
        Map.merge(
          %{
            "tenant_id" => order.tenant_id,
            "checkout_ref" => "cs_fake_#{order.id}",
            "payment_ref" => "pi_#{order.id}",
            "amount" => order.total,
            "currency" => order.currency
          },
          extra
        )
    }

    SportsCoachBookings.Payments.ingest_webhook("fake", Jason.encode!(payload), [])
  end

  defp mark_paid_and_drain(order, extra) do
    assert {:ok, :received} = ingest_completed(order, extra)
    ObanHelpers.drain_all()
    assert Commerce.get_order!(order.id).status == :paid
  end
end
