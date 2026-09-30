defmodule SportsCoachBookings.Commerce do
  @moduledoc """
  Cart, checkout, orders, and refunds. Owned by WP-13.

  One order model for packages (credit-bearing), pay-per-session drop-ins, and
  physical products. Money is `SportsCoachBookings.Core.Money` (integer minor
  units); `orders.currency` snapshots the tenant's currency and
  `orders.number` is a per-tenant human-readable sequence (e.g. `A-000123`).

  ## Lifecycle

  A customer builds a cart (`add_package_to_cart/3`, `add_product_to_cart/3`,
  `add_drop_in/2`). `checkout/3` re-prices the cart through
  `Catalog.Pricing.price_lines/3`, enforces package per-household limits and
  product availability, creates a `pending_payment` order, reserves inventory,
  and opens a hosted provider checkout. Zero-total (comp) orders skip the
  provider and go straight to `paid`.

  `payment.succeeded` marks the order `paid` exactly once, records the discount
  redemption, and publishes `order.paid` (wp-12 grants credits, wp-08 converts
  reservations to sold, wp-14 confirms holds, wp-16 sends the receipt).
  `payment.failed` and the expiry worker publish `order.expired`, which releases
  reservations. Refunds publish `order.refunded`.

  ## Integration

    * Pricing: `Catalog.Pricing.price_lines/3`.
    * Discount redemption: `Catalog.record_redemption/3` (idempotent).
    * Stock: `Inventory.reserve/2`, `Inventory.price_and_availability/1`.
    * Payments: `Payments.create_checkout/1`, `Payments.refund/4`.
    * Credits: `Credits.revocable_for/1`, `Credits.list_lots/1` (for the
      credits-used guard) and the `order.paid` / `order.refunded` events.
    * Drop-in holds: `SportsCoachBookings.Commerce.BookingHoldSource`.

  Every tenant-scoped write runs inside `Repo.with_tenant_tx/2`; events are
  published in the same transaction as the state change (transactional outbox).
  """

  import Ecto.Query

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Catalog.Pricing
  alias SportsCoachBookings.Commerce.BookingHoldSource
  alias SportsCoachBookings.Commerce.Cart
  alias SportsCoachBookings.Commerce.CartLine
  alias SportsCoachBookings.Commerce.Order
  alias SportsCoachBookings.Commerce.OrderExpiryWorker
  alias SportsCoachBookings.Commerce.OrderLine
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.Policy
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.Payments
  alias SportsCoachBookings.Repo

  @cart_ttl_minutes 30
  @default_limit_minutes 30

  ## Carts

  @doc """
  Returns the household's open cart, creating one if absent.

  The cart is scoped to the resolved tenant.
  """
  @spec get_or_create_cart(binary()) :: Cart.t()
  def get_or_create_cart(household_id) when is_binary(household_id) do
    read(fn -> ensure_cart(household_id) end)
  end

  @doc "Returns the household's open cart with its lines, or `nil`."
  @spec get_cart(binary()) :: Cart.t() | nil
  def get_cart(household_id) when is_binary(household_id) do
    read(fn -> fetch_cart(household_id) end)
  end

  @doc "Adds `quantity` of a package to the household's cart (merging duplicates)."
  @spec add_package_to_cart(binary(), binary(), pos_integer()) :: Cart.t()
  def add_package_to_cart(household_id, package_id, quantity \\ 1) do
    add_line(household_id, :package, package_id, quantity)
  end

  @doc "Adds `quantity` of a product variant to the household's cart."
  @spec add_product_to_cart(binary(), binary(), pos_integer()) :: Cart.t()
  def add_product_to_cart(household_id, variant_id, quantity \\ 1) do
    add_line(household_id, :product, variant_id, quantity)
  end

  @doc """
  Adds a held booking (drop-in) to the household's cart and returns the cart.

  `hold_id` is a booking hold created by `Bookings.create_hold/…` (wp-14). The
  hold is resolved through `SportsCoachBookings.Commerce.BookingHoldSource`.

  The `/1` form resolves the household from the hold itself.

      Commerce.add_drop_in(household_id, hold_id) :: Cart.t()
      Commerce.add_drop_in(hold_id) :: Cart.t() | {:error, :not_found}
  """
  @spec add_drop_in(binary(), binary()) :: Cart.t()
  def add_drop_in(household_id, hold_id) when is_binary(household_id) and is_binary(hold_id) do
    add_line(household_id, :drop_in, hold_id, 1)
  end

  @spec add_drop_in(binary()) :: Cart.t() | {:error, :not_found}
  def add_drop_in(hold_id) when is_binary(hold_id) do
    case BookingHoldSource.fetch_hold(hold_id) do
      {:ok, hold} -> add_drop_in(hold.household_id, hold_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Updates a cart line's quantity, deleting it when `quantity` is not positive."
  @spec update_cart_line(binary(), binary(), integer()) :: Cart.t() | {:error, :not_found}
  def update_cart_line(household_id, line_id, quantity) do
    write(fn -> do_update_cart_line(household_id, line_id, quantity) end)
  end

  @doc "Removes a cart line."
  @spec remove_cart_line(binary(), binary()) :: Cart.t() | {:error, :not_found}
  def remove_cart_line(household_id, line_id) do
    write(fn -> do_remove_cart_line(household_id, line_id) end)
  end

  @doc "Applies a discount code to the household's cart (validated at price/checkout)."
  @spec apply_discount_code(binary(), String.t() | nil) :: Cart.t()
  def apply_discount_code(household_id, code) do
    write(fn ->
      cart = ensure_cart(household_id)
      cart |> Ecto.Changeset.change(discount_code: code) |> Repo.update!() |> preload_lines()
    end)
  end

  @doc "Removes any discount code from the household's cart."
  @spec remove_discount_code(binary()) :: Cart.t()
  def remove_discount_code(household_id), do: apply_discount_code(household_id, nil)

  @doc """
  Prices the household's cart without persisting anything.

  Returns the `Catalog.Pricing.price_lines/3` result with a `description`
  (and product `available`) merged onto each line, or an error atom from
  pricing (e.g. `:invalid_code`, `:not_applicable`).
  """
  @spec price_cart(binary()) :: {:ok, map()} | {:error, term()}
  def price_cart(household_id) when is_binary(household_id) do
    read(fn ->
      case fetch_cart(household_id) do
        nil -> {:error, :empty_cart}
        cart -> resolve_and_price(cart.lines, cart.discount_code, household_id)
      end
    end)
  end

  ## Checkout

  @doc """
  Checks out the household's cart.

  Prices the cart, enforces limits and availability, creates a
  `pending_payment` order, reserves inventory, and opens a hosted provider
  checkout. Zero-total orders are marked `paid` immediately and publish
  `order.paid`.

  Returns `{:ok, %{order: Order.t(), redirect_url: String.t() | nil}}` or an
  error (e.g. `{:error, :empty_cart}`, `{:error, :invalid_code}`,
  `{:error, :provider_not_ready}`, `{:error, {:insufficient_stock, id, n}}`).
  """
  @spec checkout(Policy.actor(), binary(), keyword() | map()) ::
          {:ok, %{order: Order.t(), redirect_url: String.t() | nil}} | {:error, term()}
  def checkout(actor, household_id, opts \\ []) when is_binary(household_id) do
    write(fn -> do_checkout(actor, household_id, opts) end)
  end

  ## Offline orders

  @doc """
  Creates an already-paid order for a household on its behalf (cash/e-transfer
  at the field). Audited.

  `attrs` requires `:household_id` and `:lines` (`[%{type, ref_id, quantity}]`);
  `:discount_code` and `:note` are optional. Inventory is reserved and converted
  to sold through the normal `order.paid` flow.
  """
  @spec create_offline_order(Policy.actor(), map() | keyword()) ::
          {:ok, Order.t()} | {:error, term()}
  def create_offline_order(actor, attrs) do
    write(fn -> do_create_offline_order(actor, attrs) end)
  end

  ## Refunds

  @doc """
  Refunds all or part of an order line.

  `money` is the amount to refund; it may not exceed the line's unrefunded
  balance. For package lines, refunds whose credits have been partly used are
  blocked with `{:error, :credits_used}` unless `force: true` (audited).

  Returns `{:ok, %{line: OrderLine.t(), payment_refund: Payments.Refund.t() | nil}}`,
  `{:ok, :already_refunded}`, or an error. Idempotent per order line.
  """
  @spec refund_line(binary(), Money.t(), term(), Policy.actor()) ::
          {:ok, map()} | {:ok, :already_refunded} | {:error, term()}
  def refund_line(order_line_id, %Money{} = money, reason, actor),
    do: refund_line(order_line_id, money, reason, actor, [])

  @spec refund_line(binary(), Money.t(), term(), Policy.actor(), keyword() | map()) ::
          {:ok, map()} | {:ok, :already_refunded} | {:error, term()}
  def refund_line(order_line_id, %Money{} = money, reason, actor, opts)
      when is_binary(order_line_id) do
    write(fn -> do_refund_line(order_line_id, money, reason, actor, opts) end)
  end

  @doc """
  Refunds every not-yet-refunded line of an order. Audited. Idempotent.

  Options: `:reason`, `:force`.
  """
  @spec refund_order(Policy.actor(), binary(), keyword() | map()) ::
          {:ok, [map()]} | {:error, term()}
  def refund_order(actor, order_id, opts \\ []) when is_binary(order_id) do
    write(fn -> do_refund_order(actor, order_id, opts) end)
  end

  ## Order reads

  @doc "Lists a household's orders, newest first."
  @spec list_orders_for_household(binary()) :: [Order.t()]
  def list_orders_for_household(household_id) when is_binary(household_id) do
    read(fn ->
      Repo.all(
        from o in Order,
          where: o.household_id == ^household_id,
          order_by: [desc: o.inserted_at, desc: o.id],
          preload: [:lines]
      )
    end)
  end

  @doc "Paginates a household's orders, newest first."
  @spec page_household_orders(binary(), map() | keyword()) ::
          %{data: [Order.t()], next_cursor: binary() | nil}
  def page_household_orders(household_id, params \\ %{}) do
    paginate(from(o in Order, where: o.household_id == ^household_id, preload: [:lines]), params)
  end

  @doc "Fetches a household's order, or `{:error, :not_found}`."
  @spec fetch_household_order(binary(), binary()) :: {:ok, Order.t()} | {:error, :not_found}
  def fetch_household_order(household_id, order_id) do
    read(fn ->
      case Repo.one(
             from o in Order,
               where: o.id == ^order_id and o.household_id == ^household_id,
               preload: [:lines]
           ) do
        nil -> {:error, :not_found}
        order -> {:ok, order}
      end
    end)
  end

  @doc "Fetches an order by id, or `{:error, :not_found}`."
  @spec fetch_order(binary()) :: {:ok, Order.t()} | {:error, :not_found}
  def fetch_order(order_id) do
    read(fn -> fetch_order_in_tx(order_id) end)
  end

  @doc "Fetches an order by id, raising if absent."
  @spec get_order!(binary()) :: Order.t()
  def get_order!(order_id), do: read(fn -> Repo.get!(Order, order_id) |> Repo.preload(:lines) end)

  @doc """
  Paginates orders for the staff list.

  Filters: `:status`, `:household_id`, `:type` (line type), `:from`, `:to`
  (`inserted_at` bounds).
  """
  @spec page_orders(map() | keyword(), map() | keyword()) ::
          %{data: [Order.t()], next_cursor: binary() | nil}
  def page_orders(filters \\ %{}, params \\ %{}) do
    paginate(staff_order_query(normalize_filters(filters)), params)
  end

  ## Expiry

  @doc """
  Expires a `pending_payment` order and publishes `order.expired`.

  Idempotent: a paid, cancelled, or already-expired order is a no-op. Used by
  `OrderExpiryWorker` and the `payment.failed` subscriber.
  """
  @spec expire_order(binary()) :: {:ok, :expired | :noop | :not_found} | {:error, term()}
  def expire_order(order_id) when is_binary(order_id) do
    write(fn -> do_expire_order(order_id) end)
  end

  @doc """
  Expires every unpaid order past `now` (default: the clock), publishing
  `order.expired` for each. Returns `{:ok, expired_order_ids}`.
  """
  @spec expire_due_orders(DateTime.t()) :: {:ok, [binary()]} | {:error, term()}
  def expire_due_orders(now \\ DateTime.utc_now()) do
    write(fn -> do_expire_due_orders(now) end)
  end

  ## Integration seams

  @doc """
  Whether the resolved tenant has any paid order.

  Used by wp-01 to lock the tenant currency. When no tenant is in context this
  returns `false`. `config :sports_coach_bookings, :commerce_any_paid_orders`
  remains an explicit test override for the locked path.
  """
  @spec any_paid_orders?() :: boolean()
  def any_paid_orders? do
    case Application.get_env(:sports_coach_bookings, :commerce_any_paid_orders) do
      nil -> do_any_paid_orders?()
      value -> value == true
    end
  end

  @doc """
  The resolved household's order line ids for the portal pickup view.

  Implements `SportsCoachBookings.Inventory.OrderSource` (wp-08).
  """
  @spec order_line_ids_for_household(binary()) :: [binary()]
  def order_line_ids_for_household(household_id) when is_binary(household_id) do
    read(fn ->
      Repo.all(
        from l in OrderLine,
          join: o in Order,
          on: o.id == l.order_id,
          where: o.household_id == ^household_id and o.status in [:paid, :partially_refunded],
          select: l.id
      )
    end)
  end

  ## Order event handlers (called by subscribers)

  @doc """
  Marks a `pending_payment` order `paid`, records the redemption, and publishes
  `order.paid` exactly once. Idempotent.
  """
  @spec mark_order_paid(binary(), binary() | nil) ::
          {:ok, Order.t()} | {:ok, :already_paid} | {:error, term()}
  def mark_order_paid(order_id, payment_id \\ nil) when is_binary(order_id) do
    write(fn -> do_mark_paid(order_id, payment_id) end)
  end

  @doc """
  Reconciles an order after `payment.refunded`: updates the refunded total and
  status and publishes `order.refunded`. Idempotent per `refund_id`.
  """
  @spec reconcile_refund(map()) :: {:ok, Order.t() | :noop | :already_refunded} | {:error, term()}
  def reconcile_refund(payload) when is_map(payload) do
    order_id = field(payload, :order_id)

    if is_binary(order_id) do
      write(fn ->
        do_reconcile_refund(
          order_id,
          field(payload, :amount) || 0,
          field(payload, :payment_id),
          field(payload, :refund_id)
        )
      end)
    else
      {:ok, :noop}
    end
  end

  ## Private — cart helpers

  defp add_line(household_id, type, ref_id, quantity) do
    write(fn ->
      cart = ensure_cart(household_id)
      upsert_line(cart, type, ref_id, quantity)
      preload_lines(cart)
    end)
  end

  defp upsert_line(cart, type, ref_id, quantity) do
    case Repo.get_by(CartLine, cart_id: cart.id, type: type, ref_id: ref_id) do
      nil ->
        %CartLine{}
        |> CartLine.changeset(%{
          tenant_id: cart.tenant_id,
          cart_id: cart.id,
          type: type,
          ref_id: ref_id,
          quantity: quantity
        })
        |> Repo.insert!()

      existing ->
        existing
        |> Ecto.Changeset.change(quantity: existing.quantity + quantity)
        |> Repo.update!()
    end
  end

  defp ensure_cart(household_id) do
    case fetch_cart(household_id) do
      nil -> insert_cart(household_id)
      cart -> cart
    end
  end

  defp insert_cart(household_id) do
    expires_at = DateTime.add(now(), @cart_ttl_minutes, :minute)

    %Cart{}
    |> Cart.changeset(%{
      tenant_id: TenantContext.get_tenant_id(),
      household_id: household_id,
      expires_at: expires_at
    })
    |> Repo.insert!()
    |> preload_lines()
  end

  defp fetch_cart(household_id) do
    Repo.one(
      from c in Cart,
        where: c.household_id == ^household_id,
        order_by: [desc: c.inserted_at, desc: c.id],
        limit: 1,
        preload: [:lines]
    )
  end

  defp preload_lines(cart), do: Repo.preload(cart, :lines, force: true)

  defp do_update_cart_line(household_id, line_id, quantity) do
    case cart_line(household_id, line_id) do
      nil ->
        {:error, :not_found}

      line when quantity in [nil, 0] or quantity < 0 ->
        _ = Repo.delete!(line)
        preload_lines(ensure_cart(household_id))

      line ->
        line |> Ecto.Changeset.change(quantity: quantity) |> Repo.update!()
        preload_lines(ensure_cart(household_id))
    end
  end

  defp do_remove_cart_line(household_id, line_id) do
    case cart_line(household_id, line_id) do
      nil ->
        {:error, :not_found}

      line ->
        _ = Repo.delete!(line)
        preload_lines(ensure_cart(household_id))
    end
  end

  defp cart_line(household_id, line_id) do
    Repo.one(
      from l in CartLine,
        join: c in Cart,
        on: c.id == l.cart_id,
        where: l.id == ^line_id and c.household_id == ^household_id
    )
  end

  ## Private — pricing resolution

  defp resolve_and_price(lines, discount_code, household_id) do
    with {:ok, resolved} <- resolve_lines(lines) do
      price_resolved(resolved, discount_code, household_id)
    end
  end

  defp resolve_lines([]), do: {:ok, []}

  defp resolve_lines(lines) do
    availability = load_availability(lines)

    lines
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case resolve_line(line, availability) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_ok()
  end

  defp reverse_ok({:ok, list}), do: {:ok, Enum.reverse(list)}
  defp reverse_ok(other), do: other

  defp load_availability(lines) do
    variant_ids = for l <- lines, l.type == :product, do: l.ref_id

    if variant_ids == [] do
      %{}
    else
      Inventory.price_and_availability(variant_ids)
    end
  end

  defp resolve_line(%{type: :package} = line, _availability) do
    case Catalog.fetch_package(line.ref_id) do
      {:ok, %{active: true} = package} -> {:ok, resolved_package(line, package)}
      _ -> {:error, {:line_unavailable, line.ref_id}}
    end
  end

  defp resolve_line(%{type: :product} = line, availability) do
    case Map.get(availability, line.ref_id) do
      %{active: true, price: %Money{} = price} = info ->
        {:ok,
         %{
           type: :product,
           ref_id: line.ref_id,
           quantity: line.quantity,
           unit_price: price.amount,
           taxable: info.taxable == true,
           description: product_description(line.ref_id),
           booking_id: nil,
           available: info.available,
           per_household_limit: nil,
           credit_quantity: nil
         }}

      _ ->
        {:error, {:line_unavailable, line.ref_id}}
    end
  end

  defp resolve_line(%{type: :drop_in} = line, _availability) do
    case BookingHoldSource.fetch_hold(line.ref_id) do
      {:ok, hold} ->
        {:ok,
         %{
           type: :drop_in,
           ref_id: line.ref_id,
           quantity: line.quantity,
           unit_price: hold.unit_price,
           taxable: hold.taxable == true,
           description: hold.description || "Drop-in session",
           booking_id: hold.booking_id,
           available: nil,
           per_household_limit: nil,
           credit_quantity: nil
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolved_package(line, package) do
    %{
      type: :package,
      ref_id: package.id,
      quantity: line.quantity,
      unit_price: package.price,
      taxable: package.taxable == true,
      description: "#{package.name} (#{package.credit_quantity} credits)",
      booking_id: nil,
      available: nil,
      per_household_limit: package.per_household_limit,
      credit_quantity: package.credit_quantity
    }
  end

  defp product_description(variant_id) do
    variant = Inventory.get_variant!(variant_id)
    product = Inventory.get_product!(variant.product_id)
    options = variant.option_values |> Map.values() |> Enum.join(" / ")

    if options == "", do: product.name, else: "#{product.name} (#{options})"
  end

  defp price_resolved(resolved, discount_code, household_id) do
    inputs =
      Enum.map(resolved, fn line ->
        %{
          type: line.type,
          ref_id: line.ref_id,
          unit_price: line.unit_price,
          quantity: line.quantity,
          taxable: line.taxable
        }
      end)

    case Pricing.price_lines(inputs, discount_code, household_id) do
      {:ok, result} -> {:ok, %{result | lines: merge_resolved(resolved, result.lines)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp merge_resolved(resolved, priced) do
    Enum.zip_with(resolved, priced, fn source, line ->
      Map.merge(line, %{
        description: source.description,
        booking_id: source.booking_id,
        available: source.available,
        per_household_limit: source.per_household_limit
      })
    end)
  end

  ## Private — checkout

  defp do_checkout(actor, household_id, _opts) do
    with {:ok, cart} <- load_cart(household_id),
         {:ok, resolved} <- resolve_lines(cart.lines),
         :ok <- enforce_constraints(household_id, resolved),
         {:ok, priced} <- price_resolved(resolved, cart.discount_code, household_id),
         {:ok, order} <- create_order(actor, household_id, priced, :online),
         {:ok, _reserved} <- reserve_stock(order, resolved) do
      finalize_checkout(order, actor, household_id)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp load_cart(household_id) do
    case fetch_cart(household_id) do
      nil -> {:error, :empty_cart}
      cart -> {:ok, cart}
    end
  end

  defp finalize_checkout(order, actor, household_id) do
    order = preload_order_lines(order)

    if order.total == 0 do
      {:ok, order} = do_mark_paid(order.id, nil)
      _ = delete_cart(household_id)
      _ = Audit.record(actor, "commerce.order.comped", order, %{total: 0})
      {:ok, %{order: order, redirect_url: nil}}
    else
      start_provider_checkout(order, actor, household_id)
    end
  end

  defp start_provider_checkout(order, actor, household_id) do
    case Payments.create_checkout(checkout_payload(order, actor)) do
      {:ok, url} ->
        _ = delete_cart(household_id)
        {:ok, %{order: order, redirect_url: url}}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp checkout_payload(order, actor) do
    %{
      id: order.id,
      number: order.number,
      currency: order.currency,
      total: order.total,
      customer_email: customer_email(actor),
      line_items:
        Enum.map(order.lines, fn line ->
          %{name: line.description, unit_amount: line.line_total, quantity: 1}
        end)
    }
  end

  defp customer_email(%CustomerActor{customer_user: %{email: email}}), do: email
  defp customer_email(_actor), do: nil

  defp delete_cart(household_id) do
    case fetch_cart(household_id) do
      nil ->
        :ok

      cart ->
        _ = Repo.delete!(cart)
        :ok
    end
  end

  defp do_create_offline_order(actor, attrs) do
    household_id = field(attrs, :household_id)
    raw_lines = attrs |> field(:lines) |> normalize_raw_lines()
    discount_code = field(attrs, :discount_code)

    if is_binary(household_id) do
      create_offline(actor, household_id, raw_lines, discount_code)
    else
      {:error, :household_required}
    end
  end

  defp create_offline(actor, household_id, raw_lines, discount_code) do
    with {:ok, resolved} <- resolve_lines(raw_lines),
         :ok <- enforce_constraints(household_id, resolved),
         {:ok, priced} <- price_resolved(resolved, discount_code, household_id),
         {:ok, order} <- create_order(actor, household_id, priced, :offline),
         {:ok, _reserved} <- reserve_stock(order, resolved),
         {:ok, order} <- do_mark_paid(order.id, nil) do
      _ =
        Audit.record(actor, "commerce.order.created_offline", order, %{
          household_id: household_id
        })

      {:ok, order}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_raw_lines(nil), do: []

  defp normalize_raw_lines(lines) when is_list(lines) do
    Enum.map(lines, fn line ->
      %{
        type: normalize_type(field(line, :type)),
        ref_id: field(line, :ref_id),
        quantity: field(line, :quantity) || 1
      }
    end)
  end

  defp normalize_type(type) when type in [:package, :product, :drop_in], do: type
  defp normalize_type("package"), do: :package
  defp normalize_type("product"), do: :product
  defp normalize_type("drop_in"), do: :drop_in
  defp normalize_type(other), do: other

  defp create_order(actor, household_id, priced, payment_method) do
    {actor_type, actor_id} = actor_fields(actor)

    attrs = %{
      tenant_id: TenantContext.get_tenant_id(),
      number: next_number(),
      household_id: household_id,
      placed_by_type: actor_type,
      placed_by_id: actor_id,
      status: :pending_payment,
      currency: tenant_currency(),
      subtotal: priced.subtotal,
      discount_total: priced.discount_total,
      tax_total: priced.tax_total,
      total: priced.total,
      discount_id: discount_id(priced),
      payment_method: payment_method,
      expires_at: DateTime.add(now(), @default_limit_minutes, :minute)
    }

    order = %Order{} |> Order.changeset(attrs) |> Repo.insert!()
    lines = Enum.map(priced.lines, &insert_order_line(order, &1))
    order = %{order | lines: lines}
    if payment_method == :online and order.total > 0, do: schedule_expiry(order)
    {:ok, order}
  end

  defp insert_order_line(order, line) do
    attrs = %{
      tenant_id: order.tenant_id,
      order_id: order.id,
      type: line.type,
      ref_id: line.ref_id,
      booking_id: Map.get(line, :booking_id),
      description: line.description,
      unit_price: line.unit_price,
      quantity: line.quantity,
      discount_amount: line.discount_amount,
      tax_amount: line.tax_amount,
      line_total: line.line_total,
      taxable: line.taxable
    }

    %OrderLine{} |> OrderLine.changeset(attrs) |> Repo.insert!()
  end

  defp schedule_expiry(order) do
    %{"tenant_id" => order.tenant_id, "order_id" => order.id}
    |> OrderExpiryWorker.new(scheduled_at: order.expires_at)
    |> Oban.insert()
  end

  defp discount_id(%{discount: nil}), do: nil
  defp discount_id(%{discount: discount}), do: discount.id

  defp reserve_stock(_order, []), do: {:ok, :none}

  defp reserve_stock(order, resolved) do
    lines =
      resolved
      |> Enum.filter(&(&1.type == :product))
      |> Enum.map(&%{variant_id: &1.ref_id, quantity: &1.quantity})

    if lines == [] do
      {:ok, :none}
    else
      Inventory.reserve(order.id, lines)
    end
  end

  defp next_number do
    tenant_id = TenantContext.get_tenant_id()

    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "order_number:#{tenant_id}"
    ])

    next =
      case Repo.one(from o in Order, select: max(o.number)) do
        nil -> 1
        number -> String.to_integer(String.trim_leading(number, "A-")) + 1
      end

    "A-" <> String.pad_leading(Integer.to_string(next), 6, "0")
  end

  ## Private — constraints

  defp enforce_constraints(household_id, resolved) do
    with :ok <- enforce_stock(resolved) do
      enforce_package_limits(household_id, resolved)
    end
  end

  defp enforce_stock(resolved) do
    resolved
    |> Enum.filter(&(&1.type == :product and is_integer(&1.available)))
    |> Enum.reduce_while(:ok, fn line, :ok ->
      if line.available >= line.quantity do
        {:cont, :ok}
      else
        {:halt, {:error, {:insufficient_stock, line.ref_id, line.available}}}
      end
    end)
  end

  defp enforce_package_limits(_household_id, []), do: :ok

  defp enforce_package_limits(household_id, resolved) do
    resolved
    |> Enum.filter(&(&1.type == :package and is_integer(&1.per_household_limit)))
    |> Enum.reduce_while(:ok, fn line, :ok ->
      purchased = purchased_package_quantity(household_id, line.ref_id)

      if purchased + line.quantity <= line.per_household_limit do
        {:cont, :ok}
      else
        {:halt, {:error, :household_limit_reached}}
      end
    end)
  end

  defp purchased_package_quantity(household_id, package_id) do
    Repo.one(
      from l in OrderLine,
        join: o in Order,
        on: o.id == l.order_id,
        where:
          o.household_id == ^household_id and
            o.status in [:paid, :partially_refunded] and
            l.type == :package and l.ref_id == ^package_id,
        select: coalesce(sum(l.quantity), 0)
    )
  end

  ## Private — paid transition

  defp do_mark_paid(order_id, payment_id) do
    {count, _} =
      Repo.update_all(
        from(o in Order, where: o.id == ^order_id and o.status == :pending_payment),
        set: [status: :paid, paid_at: now(), payment_id: payment_id, updated_at: now()]
      )

    if count > 0 do
      order = Repo.get!(Order, order_id) |> preload_order_lines()
      record_redemption(order)
      publish_order_paid(order)
      {:ok, order}
    else
      {:ok, :already_paid}
    end
  end

  defp record_redemption(%Order{discount_id: nil}), do: :ok

  defp record_redemption(%Order{discount_id: discount_id} = order) do
    _ = Pricing.record_redemption(discount_id, order.household_id, order.id)
    :ok
  end

  defp publish_order_paid(order) do
    Events.publish("order.paid", %{
      order_id: order.id,
      tenant_id: order.tenant_id,
      household_id: order.household_id,
      lines: order_paid_lines(order.lines)
    })
  end

  defp order_paid_lines(lines) do
    Enum.map(lines, fn line ->
      base = %{order_line_id: line.id, quantity: line.quantity}

      case line.type do
        :package -> Map.put(base, :package_id, line.ref_id)
        :product -> Map.put(base, :variant_id, line.ref_id)
        :drop_in -> Map.put(base, :booking_id, line.booking_id || line.ref_id)
      end
    end)
  end

  ## Private — refunds

  defp do_refund_order(actor, order_id, opts) do
    reason = field(opts, :reason) || "requested_by_customer"
    force = field(opts, :force) == true

    case lock_order(order_id) do
      nil ->
        {:error, :not_found}

      %Order{} = order ->
        refund_all_lines(actor, preload_order_lines(order), reason, force)
    end
  end

  defp refund_all_lines(actor, order, reason, force) do
    if Order.refundable?(order) do
      order.lines
      |> Enum.filter(&(&1.refunded_amount < &1.line_total))
      |> refund_each_line(actor, order, reason, force)
    else
      {:error, :not_refundable}
    end
  end

  defp refund_each_line(lines, actor, order, reason, force) do
    lines
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case refund_line_of(actor, order, line, reason, force) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      other -> other
    end
  end

  defp refund_line_of(actor, order, line, reason, force) do
    money = Money.new(OrderLine.refundable_amount(line), order.currency)
    do_refund_line(line.id, money, reason, actor, force: force)
  end

  defp do_refund_line(order_line_id, money, reason, actor, opts) do
    force = field(opts, :force) == true

    case lock_order_line(order_line_id) do
      nil ->
        {:error, :not_found}

      line ->
        order = lock_order(line.order_id)

        case refund_check(line, order, money, force) do
          :ok -> perform_refund(line, order, money, reason, actor, force)
          other -> other
        end
    end
  end

  defp refund_check(_line, nil, _money, _force), do: {:error, :not_found}

  defp refund_check(line, order, money, force) do
    cond do
      not Order.refundable?(order) -> {:error, :not_refundable}
      line.refunded_amount >= line.line_total -> {:ok, :already_refunded}
      money.amount <= 0 -> {:error, :invalid_amount}
      money.amount > OrderLine.refundable_amount(line) -> {:error, :amount_exceeds_line}
      not force and credits_used?(order.household_id, line) -> {:error, :credits_used}
      true -> :ok
    end
  end

  defp perform_refund(line, order, money, reason, actor, force) do
    case provider_refund(order, money, reason, actor) do
      {:ok, provider_result} ->
        updated = apply_line_refund(line, money.amount, provider_refund_ref(provider_result))

        if provider_result == :offline do
          order = apply_order_refund(order, line, money.amount)
          publish_order_refunded(preload_order_lines(order))
        end

        audit_refund(actor, order, updated, money, force)
        {:ok, %{line: updated, payment_refund: payment_refund(provider_result)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp provider_refund(%Order{payment_id: nil}, _money, _reason, _actor), do: {:ok, :offline}

  defp provider_refund(%Order{payment_id: payment_id}, money, reason, actor) do
    case Payments.refund(payment_id, money, reason, actor) do
      {:ok, refund} -> {:ok, refund}
      {:error, reason} -> {:error, reason}
    end
  end

  defp provider_refund_ref(%Payments.Refund{refund_ref: ref}), do: ref
  defp provider_refund_ref(_result), do: nil

  defp payment_refund(%Payments.Refund{} = refund), do: refund
  defp payment_refund(_result), do: nil

  defp apply_line_refund(line, amount, refund_ref) do
    line
    |> Ecto.Changeset.change(
      refunded_amount: line.refunded_amount + amount,
      refund_ref: refund_ref || line.refund_ref,
      updated_at: now()
    )
    |> Repo.update!()
  end

  defp apply_order_refund(order, line, amount) do
    refunded_total = min(order.total, order.refunded_total + amount)
    ref = "offline:#{line.id}"

    order
    |> Ecto.Changeset.change(
      refunded_total: refunded_total,
      status: refund_status(order, refunded_total),
      refunded_refs: Enum.uniq([ref | order.refunded_refs || []]),
      updated_at: now()
    )
    |> Repo.update!()
  end

  defp refund_status(order, refunded_total) do
    if order.total > 0 and refunded_total >= order.total, do: :refunded, else: :partially_refunded
  end

  defp audit_refund(actor, order, line, money, force) do
    Audit.record(actor, "commerce.order_line.refunded", line, %{
      order_id: order.id,
      amount: money.amount,
      forced: force
    })
  end

  defp credits_used?(household_id, %OrderLine{type: :package} = line) do
    Credits.list_lots(household_id)
    |> Enum.find(&(&1.order_line_id == line.id))
    |> case do
      nil -> false
      lot -> lot.quantity_granted > lot.remaining
    end
  end

  defp credits_used?(_household_id, _line), do: false

  ## Private — refund reconciliation

  defp do_reconcile_refund(order_id, amount, payment_id, refund_id) do
    case lock_order(order_id) do
      nil ->
        {:ok, :noop}

      order ->
        key = refund_id || "provider:#{payment_id}:#{amount}"

        if key in (order.refunded_refs || []) do
          {:ok, :already_refunded}
        else
          reconcile_order(order, key, amount)
        end
    end
  end

  defp reconcile_order(order, key, amount) do
    refunded_total = min(order.total, order.refunded_total + amount)

    order =
      order
      |> Ecto.Changeset.change(
        refunded_total: refunded_total,
        status: refund_status(order, refunded_total),
        refunded_refs: [key | order.refunded_refs || []],
        updated_at: now()
      )
      |> Repo.update!()
      |> preload_order_lines()

    publish_order_refunded(order)
    {:ok, order}
  end

  defp publish_order_refunded(order) do
    lines =
      case Enum.filter(order.lines || [], &(&1.refunded_amount > 0)) do
        [] -> order.lines || []
        refunded -> refunded
      end

    Events.publish("order.refunded", %{
      order_id: order.id,
      tenant_id: order.tenant_id,
      household_id: order.household_id,
      lines: Enum.map(lines, &%{order_line_id: &1.id})
    })
  end

  ## Private — expiry

  defp do_expire_order(order_id) do
    case Repo.get(Order, order_id) do
      nil -> {:ok, :not_found}
      %Order{} = order -> expire_pending(order)
    end
  end

  defp expire_pending(%Order{status: :pending_payment} = order) do
    {count, _} =
      Repo.update_all(
        from(o in Order, where: o.id == ^order.id and o.status == :pending_payment),
        set: [status: :expired, updated_at: now()]
      )

    if count > 0 do
      Events.publish("order.expired", %{order_id: order.id, tenant_id: order.tenant_id})
      {:ok, :expired}
    else
      {:ok, :noop}
    end
  end

  defp expire_pending(_order), do: {:ok, :noop}

  defp do_expire_due_orders(now) do
    ids =
      Repo.all(
        from o in Order,
          where:
            o.status == :pending_payment and not is_nil(o.expires_at) and
              o.expires_at <= ^now,
          select: o.id,
          order_by: [asc: o.expires_at, asc: o.id]
      )

    Enum.each(ids, fn id ->
      _ = expire_pending(Repo.get!(Order, id))
    end)

    {:ok, ids}
  end

  ## Private — staff queries

  defp staff_order_query(filters) do
    Order
    |> preload([:lines])
    |> filter_status(filters)
    |> filter_household(filters)
    |> filter_type(filters)
    |> filter_dates(filters)
  end

  defp filter_status(query, filters) do
    case normalize_status(field(filters, :status)) do
      nil -> query
      status -> where(query, [o], o.status == ^status)
    end
  end

  defp filter_household(query, filters) do
    case field(filters, :household_id) do
      nil -> query
      household_id -> where(query, [o], o.household_id == ^household_id)
    end
  end

  defp filter_type(query, filters) do
    case field(filters, :type) do
      nil ->
        query

      type ->
        type = normalize_type(type)

        query
        |> join(:inner, [o], l in OrderLine, on: l.order_id == o.id and l.type == ^type)
        |> distinct(true)
    end
  end

  defp filter_dates(query, filters) do
    query
    |> filter_from(field(filters, :from))
    |> filter_to(field(filters, :to))
  end

  defp filter_from(query, nil), do: query

  defp filter_from(query, from) do
    case parse_datetime(from) do
      {:ok, dt} -> where(query, [o], o.inserted_at >= ^dt)
      :error -> query
    end
  end

  defp filter_to(query, nil), do: query

  defp filter_to(query, to) do
    case parse_datetime(to) do
      {:ok, dt} -> where(query, [o], o.inserted_at <= ^dt)
      :error -> query
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: {:ok, dt}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp normalize_status(nil), do: nil

  defp normalize_status(status) do
    status = to_string(status)

    Enum.find(Order.statuses(), fn candidate ->
      Atom.to_string(candidate) == status
    end)
  end

  ## Private — locks and reads

  defp lock_order(nil), do: nil

  defp lock_order(order_id) do
    Repo.one(from o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")
  end

  defp lock_order_line(nil), do: nil

  defp lock_order_line(order_line_id) do
    Repo.one(from l in OrderLine, where: l.id == ^order_line_id, lock: "FOR UPDATE")
  end

  defp fetch_order_in_tx(order_id) do
    case Repo.get(Order, order_id) do
      nil -> {:error, :not_found}
      order -> {:ok, preload_order_lines(order)}
    end
  end

  defp preload_order_lines(order), do: Repo.preload(order, :lines)

  defp do_any_paid_orders? do
    case TenantContext.get_tenant_id() do
      nil ->
        false

      _tenant_id ->
        read(fn ->
          Repo.exists?(
            from o in Order, where: o.status in [:paid, :partially_refunded, :refunded]
          )
        end)
    end
  end

  ## Private — shared plumbing

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp write(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp paginate(query, params) do
    read(fn ->
      {rows, next_cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: next_cursor}
    end)
  end

  defp tenant_currency do
    case TenantContext.get_tenant() do
      %{currency: currency} when is_binary(currency) -> currency
      _ -> "CAD"
    end
  end

  defp actor_fields(%StaffActor{staff_user_id: id}), do: {"StaffActor", id}
  defp actor_fields(%CustomerActor{customer_user_id: id}), do: {"CustomerActor", id}
  defp actor_fields(_actor), do: {nil, nil}

  defp normalize_filters(filters), do: Enum.into(filters, %{})

  defp field(container, key) when is_map(container) do
    Map.get(container, key) || Map.get(container, to_string(key))
  end

  defp field(container, key) when is_list(container), do: Keyword.get(container, key)
  defp field(_container, _key), do: nil

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
