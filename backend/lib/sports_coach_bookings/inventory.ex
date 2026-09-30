defmodule SportsCoachBookings.Inventory do
  @moduledoc """
  Products, variants, stock, and pickups. Owned by WP-08.

  All functions are tenant-scoped: callers place the tenant in context (via
  `SportsCoachBookingsWeb.Plugs.ResolveTenant` in requests or
  `SportsCoachBookings.DataCase.put_tenant/1` in tests) and every function runs
  inside `SportsCoachBookings.Repo.with_tenant_tx/2` (or a transaction with the
  tenant GUC set) so the RLS policies apply.

  Stock is a ledger. `stock_levels.on_hand` always equals the sum of the
  non-reservation `stock_movements` (`received | sold | adjusted | returned`)
  and `reserved` equals the sum of the reservation movements
  (`reserved | released`).

  The Commerce-facing API is `price_and_availability/1` and `reserve/2`;
  `SportsCoachBookings.Inventory.OrderEventsSubscriber` reacts to the order
  lifecycle events.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.Policy
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Core.Types.UUIDv7
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Inventory.Fulfillment
  alias SportsCoachBookings.Inventory.OrderSource
  alias SportsCoachBookings.Inventory.Product
  alias SportsCoachBookings.Inventory.ProductVariant
  alias SportsCoachBookings.Inventory.StockLevel
  alias SportsCoachBookings.Inventory.StockMovement
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Tenancy.Storage

  @availability_sold_out "sold out"
  @availability_low "low stock"
  @availability_in "in stock"

  ## Products

  @doc "Lists products, optionally filtered by `:active` and `:visible_in_portal`."
  @spec list_products(map() | keyword()) :: [Product.t()]
  def list_products(filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      Product
      |> where_active(filters)
      |> where_visible(filters)
      |> order_by([p], asc: p.position, asc: p.name)
      |> Repo.all()
    end)
  end

  @doc "Paginates products. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_products(map() | keyword(), map() | keyword()) ::
          %{data: [Product.t()], next_cursor: binary() | nil}
  def page_products(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)
    paginate(Product |> where_active(filters) |> where_visible(filters), params)
  end

  @doc "Fetches a product, raising if it does not exist for this tenant."
  @spec get_product!(binary()) :: Product.t()
  def get_product!(id), do: read(fn -> Repo.get!(Product, id) end)

  @doc "Fetches a product, returning `{:error, :not_found}` when absent."
  @spec fetch_product(binary()) :: {:ok, Product.t()} | {:error, :not_found}
  def fetch_product(id), do: read(fn -> fetch_record(Product, id) end)

  @doc "Creates a product and records an audit event."
  @spec create_product(Policy.actor(), map() | keyword()) ::
          {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create_product(actor, attrs) do
    Multi.new()
    |> Multi.insert(:product, Product.changeset(%Product{}, tenant_attrs(attrs)))
    |> Multi.run(:audit, fn _repo, %{product: product} ->
      Audit.record(actor, "inventory.product.created", product, %{})
    end)
    |> run_multi(:product)
  end

  @doc "Updates a product."
  @spec update_product(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, Product.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_product(actor, id, attrs) do
    with_loaded(Product, id, fn product ->
      Multi.new()
      |> Multi.update(:product, Product.changeset(product, attrs))
      |> Multi.run(:audit, fn _repo, %{product: product} ->
        Audit.record(actor, "inventory.product.updated", product, %{})
      end)
      |> run_multi(:product)
    end)
  end

  @doc "Archives (deactivates) a product instead of deleting it."
  @spec archive_product(Policy.actor(), binary()) ::
          {:ok, Product.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_product(actor, id), do: update_product(actor, id, %{active: false})

  @doc "Reorders products by assigning `position` from the given id order."
  @spec reorder_products(Policy.actor(), [binary()]) ::
          {:ok, [Product.t()]} | {:error, :not_found}
  def reorder_products(actor, ids) when is_list(ids) do
    read(fn -> do_reorder_products(actor, ids) end)
  end

  defp do_reorder_products(actor, ids) do
    result =
      ids
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {id, position}, {:ok, acc} ->
        case reposition(Product, id, position) do
          {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, records} ->
        {:ok, _} = Audit.record(actor, "inventory.product.reordered", nil, %{ids: ids})
        {:ok, Enum.reverse(records)}

      other ->
        other
    end
  end

  ## Variants

  @doc "Lists a product's variants, optionally filtered by `:active`."
  @spec list_variants(binary(), map() | keyword()) :: [ProductVariant.t()]
  def list_variants(product_id, filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      ProductVariant
      |> where([v], v.product_id == ^product_id)
      |> where_active(filters)
      |> order_by([v], asc: v.sku)
      |> Repo.all()
    end)
  end

  @doc "Paginates a product's variants."
  @spec page_variants(binary(), map() | keyword(), map() | keyword()) ::
          %{data: [ProductVariant.t()], next_cursor: binary() | nil}
  def page_variants(product_id, filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)

    query =
      ProductVariant
      |> where([v], v.product_id == ^product_id)
      |> where_active(filters)

    paginate(query, params)
  end

  @doc "Fetches a variant, raising if it does not exist for this tenant."
  @spec get_variant!(binary()) :: ProductVariant.t()
  def get_variant!(id), do: read(fn -> Repo.get!(ProductVariant, id) end)

  @doc "Fetches a variant, returning `{:error, :not_found}` when absent."
  @spec fetch_variant(binary()) :: {:ok, ProductVariant.t()} | {:error, :not_found}
  def fetch_variant(id), do: read(fn -> fetch_record(ProductVariant, id) end)

  @doc """
  Creates a variant for a product and initialises its stock level to zero.

  Records an audit event.
  """
  @spec create_variant(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, ProductVariant.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def create_variant(actor, product_id, attrs) do
    Multi.new()
    |> Multi.run(:product, fn _repo, _changes -> fetch_record(Product, product_id) end)
    |> Multi.run(:variant, fn _repo, _changes -> insert_variant(product_id, attrs) end)
    |> Multi.run(:stock_level, fn _repo, %{variant: variant} -> ensure_level(variant.id) end)
    |> Multi.run(:audit, fn _repo, %{variant: variant} ->
      Audit.record(actor, "inventory.variant.created", variant, %{})
    end)
    |> run_multi(:variant)
  end

  @doc "Updates a variant."
  @spec update_variant(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, ProductVariant.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_variant(actor, id, attrs) do
    with_loaded(ProductVariant, id, fn variant ->
      Multi.new()
      |> Multi.update(:variant, ProductVariant.changeset(variant, attrs))
      |> Multi.run(:audit, fn _repo, %{variant: variant} ->
        Audit.record(actor, "inventory.variant.updated", variant, %{})
      end)
      |> run_multi(:variant)
    end)
  end

  @doc "Archives (deactivates) a variant instead of deleting it."
  @spec archive_variant(Policy.actor(), binary()) ::
          {:ok, ProductVariant.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_variant(actor, id), do: update_variant(actor, id, %{active: false})

  ## Pricing + availability (Commerce API)

  @doc """
  Prices and availability for a list of variant ids.

  Returns a map keyed by variant id:

      %{
        variant_id => %{
          price: %SportsCoachBookings.Core.Money{},
          available: integer,
          taxable: boolean,
          active: boolean
        }
      }

  Missing variants are omitted. Availability is `on_hand - reserved`.
  """
  @spec price_and_availability([binary()]) :: %{optional(binary()) => map()}
  def price_and_availability(variant_ids) when is_list(variant_ids) do
    variant_ids = Enum.uniq(variant_ids)
    read(fn -> availability_map(variant_ids) end)
  end

  defp availability_map([]), do: %{}

  defp availability_map(variant_ids) do
    currency = tenant_currency()

    rows =
      Repo.all(
        from v in ProductVariant,
          join: p in Product,
          on: p.id == v.product_id,
          left_join: s in StockLevel,
          on: s.variant_id == v.id and is_nil(s.venue_id),
          where: v.id in ^variant_ids,
          select: %{
            id: v.id,
            price: v.price,
            active: v.active,
            taxable: p.taxable,
            on_hand: coalesce(s.on_hand, 0),
            reserved: coalesce(s.reserved, 0)
          }
      )

    Map.new(rows, fn row ->
      {row.id,
       %{
         price: Money.new(row.price, currency),
         available: row.on_hand - row.reserved,
         taxable: row.taxable,
         active: row.active
       }}
    end)
  end

  ## Reservations (Commerce API)

  @doc """
  Reserves stock for an order's lines.

  `lines` is a list of `%{variant_id: id, quantity: n}` (string or atom keys).
  The rows are locked `FOR UPDATE` in `variant_id` order so concurrent
  reservations cannot oversell and cannot deadlock. Either every line reserves
  or none does.

  Idempotent: reserving twice for the same order/variant is a no-op. Returns
  `{:ok, %{reservations: [...]}}` or
  `{:error, {:insufficient_stock, variant_id, available}}`.
  """
  @spec reserve(binary(), [map()]) ::
          {:ok, map()} | {:error, {:insufficient_stock, binary(), integer()}}
  def reserve(order_id, lines) when is_binary(order_id) and is_list(lines) do
    lines =
      lines
      |> Enum.map(&normalize_line/1)
      |> Enum.reject(&is_nil(&1.variant_id))
      |> Enum.sort_by(& &1.variant_id)

    multi =
      Multi.new()
      |> Multi.run(:reservations, fn _repo, _changes -> do_reserve(order_id, lines) end)

    case run_multi(multi, :reservations) do
      {:ok, reservations} -> {:ok, %{reservations: reservations}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Releases every active reservation for `order_id` (order expired/cancelled).

  Idempotent: a second call is a no-op. Returns `{:ok, released_movements}`.
  """
  @spec release_order(binary()) :: {:ok, [StockMovement.t()]} | {:error, term()}
  def release_order(order_id) when is_binary(order_id) do
    multi =
      Multi.new()
      |> Multi.run(:released, fn _repo, _changes -> do_release_order(order_id) end)

    case run_multi(multi, :released) do
      {:ok, released} -> {:ok, released}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Converts an order's active reservations to sales (`order.paid`).

  Decrements `on_hand` and `reserved`, writes `sold` and `released` movements,
  creates fulfillments from `lines` when given, and emits `stock.low` for any
  variant that fell to/below its threshold. Idempotent: replaying the event does
  not double-sell, double-fulfill, or re-emit a same-day alert.
  """
  @spec mark_order_paid(binary(), [map()] | nil) ::
          {:ok, %{sold: [map()], fulfillments: [Fulfillment.t()]}} | {:error, term()}
  def mark_order_paid(order_id, lines \\ nil) when is_binary(order_id) do
    lines = normalize_order_lines(lines)

    multi =
      Multi.new()
      |> Multi.run(:sold, fn _repo, _changes -> do_convert_to_sold(order_id) end)
      |> Multi.run(:fulfillments, fn _repo, _changes ->
        do_create_fulfillments(order_id, lines)
      end)
      |> Multi.run(:low_stock, fn _repo, %{sold: sold} -> maybe_emit_low_stock(sold) end)

    case run_multi_changes(multi) do
      {:ok, %{sold: sold, fulfillments: fulfillments}} ->
        {:ok, %{sold: sold, fulfillments: fulfillments}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Restocks a refunded order's lines. Admin choice, never automatic; the
  `order.refunded` subscriber does not call this.

  `lines` is a list of `%{variant_id: id, quantity: n, note: note}`. Idempotent
  per order/variant. Returns `{:ok, movements}`.
  """
  @spec restock_refund(Policy.actor(), binary(), [map()]) ::
          {:ok, [StockMovement.t()]} | {:error, term()}
  def restock_refund(actor, order_id, lines) when is_binary(order_id) and is_list(lines) do
    lines = Enum.map(lines, &normalize_line/1)

    multi =
      Multi.new()
      |> Multi.run(:restocked, fn _repo, _changes -> do_restock(actor, order_id, lines) end)

    case run_multi(multi, :restocked) do
      {:ok, movements} -> {:ok, movements}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Stock receive / adjust / history

  @doc "Receives `quantity` units of a variant, writing a `received` movement."
  @spec receive_stock(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, StockMovement.t()} | {:error, term()}
  def receive_stock(actor, variant_id, attrs) do
    with {:ok, quantity} <- positive_quantity(attrs) do
      unwrap(
        Repo.with_tenant_tx(fn ->
          do_receive(actor, variant_id, quantity, fetch_attr(attrs, :note))
        end)
      )
    end
  end

  @doc """
  Adjusts on-hand stock by a signed `delta` with a required reason.

  Returns `{:error, {:stock_below_reserved, variant_id}}` when the adjustment
  would drop `on_hand` below `reserved`.
  """
  @spec adjust_stock(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, StockMovement.t()} | {:error, term()}
  def adjust_stock(actor, variant_id, attrs) do
    with {:ok, delta} <- signed_delta(attrs),
         {:ok, reason} <- required_reason(attrs) do
      unwrap(
        Repo.with_tenant_tx(fn ->
          do_adjust(actor, variant_id, delta, reason)
        end)
      )
    end
  end

  @doc "Lists a variant's movements, newest first."
  @spec list_movements(binary()) :: [StockMovement.t()]
  def list_movements(variant_id) do
    read(fn ->
      Repo.all(
        from m in StockMovement,
          where: m.variant_id == ^variant_id,
          order_by: [desc: m.inserted_at, desc: m.id]
      )
    end)
  end

  @doc "Paginates a variant's movements, newest first."
  @spec page_movements(binary(), map() | keyword()) ::
          %{data: [StockMovement.t()], next_cursor: binary() | nil}
  def page_movements(variant_id, params \\ %{}) do
    paginate(from(m in StockMovement, where: m.variant_id == ^variant_id), params)
  end

  @doc "Lists stock levels, optionally filtered by `:variant_id`."
  @spec list_stock_levels(map() | keyword()) :: [StockLevel.t()]
  def list_stock_levels(filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      StockLevel
      |> where_variant(filters)
      |> order_by([s], asc: s.inserted_at)
      |> Repo.all()
    end)
  end

  @doc "Fetches a variant's single-location stock level, or `nil`."
  @spec fetch_stock_level(binary()) :: StockLevel.t() | nil
  def fetch_stock_level(variant_id) do
    read(fn ->
      Repo.one(
        from s in StockLevel,
          where: s.variant_id == ^variant_id and is_nil(s.venue_id),
          limit: 1
      )
    end)
  end

  @doc "Reconciles a variant's stored `on_hand` against its movement ledger."
  @spec reconcile_on_hand(binary()) ::
          {:ok, integer()}
          | {:error, :not_found}
          | {:error, {:reconciliation_failed, integer(), integer() | nil}}
  def reconcile_on_hand(variant_id) do
    read(fn -> do_reconcile(variant_id) end)
  end

  defp do_reconcile(variant_id) do
    case Repo.get(ProductVariant, variant_id) do
      nil -> {:error, :not_found}
      _variant -> compare_ledger(variant_id)
    end
  end

  defp compare_ledger(variant_id) do
    ledger_sum = ledger_on_hand(variant_id)
    level = Repo.one(from s in StockLevel, where: s.variant_id == ^variant_id)

    if level && level.on_hand == ledger_sum do
      {:ok, ledger_sum}
    else
      {:error, {:reconciliation_failed, ledger_sum, level && level.on_hand}}
    end
  end

  ## Fulfillments

  @doc "Lists fulfillments, optionally filtered by `:status` and `:order_line_id`."
  @spec list_fulfillments(map() | keyword()) :: [Fulfillment.t()]
  def list_fulfillments(filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      Fulfillment
      |> where_status(filters)
      |> where_order_line(filters)
      |> order_by([f], desc: f.inserted_at)
      |> Repo.all()
    end)
  end

  @doc "Paginates fulfillments (the staff pickup queue)."
  @spec page_fulfillments(map() | keyword(), map() | keyword()) ::
          %{data: [Fulfillment.t()], next_cursor: binary() | nil}
  def page_fulfillments(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)

    query =
      Fulfillment
      |> where_status(filters)
      |> where_order_line(filters)

    paginate(query, params)
  end

  @doc "Fetches a fulfillment, returning `{:error, :not_found}` when absent."
  @spec fetch_fulfillment(binary()) :: {:ok, Fulfillment.t()} | {:error, :not_found}
  def fetch_fulfillment(id), do: read(fn -> fetch_record(Fulfillment, id) end)

  @doc "Marks a fulfillment ready for pickup. Idempotent."
  @spec mark_ready(Policy.actor(), binary()) ::
          {:ok, Fulfillment.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def mark_ready(actor, id) do
    with_loaded(Fulfillment, id, fn fulfillment -> do_mark_ready(actor, fulfillment) end)
  end

  defp do_mark_ready(_actor, %{status: status} = fulfillment)
       when status in [:ready_for_pickup, :picked_up],
       do: {:ok, fulfillment}

  defp do_mark_ready(actor, fulfillment) do
    Multi.new()
    |> Multi.update(
      :fulfillment,
      Fulfillment.changeset(fulfillment, %{status: :ready_for_pickup})
    )
    |> Multi.run(:audit, fn _repo, %{fulfillment: updated} ->
      Audit.record(actor, "inventory.fulfillment.ready", updated, %{})
    end)
    |> run_multi(:fulfillment)
  end

  @doc "Marks a fulfillment picked up, recording who and when. Idempotent."
  @spec mark_picked_up(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, Fulfillment.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def mark_picked_up(actor, id, attrs \\ %{}) do
    with_loaded(Fulfillment, id, fn fulfillment ->
      do_mark_picked_up(actor, fulfillment, attrs)
    end)
  end

  defp do_mark_picked_up(_actor, %{status: :picked_up} = fulfillment, _attrs),
    do: {:ok, fulfillment}

  defp do_mark_picked_up(actor, fulfillment, attrs) do
    {_type, actor_id} = actor_fields(actor)

    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.put(:status, :picked_up)
      |> Map.put(:picked_up_at, DateTime.utc_now())
      |> Map.put(:picked_up_by, actor_id)

    Multi.new()
    |> Multi.update(:fulfillment, Fulfillment.changeset(fulfillment, attrs))
    |> Multi.run(:audit, fn _repo, %{fulfillment: updated} ->
      Audit.record(actor, "inventory.fulfillment.picked_up", updated, %{})
    end)
    |> run_multi(:fulfillment)
  end

  @doc """
  Pickup status for a household, using `Inventory.OrderSource` for its order
  line ids. Returns `[Fulfillment.t()]`. Commerce (wp-13) supplies the ids once
  merged; until then the stub returns `[]`.
  """
  @spec pickup_status_for_household(binary()) :: [Fulfillment.t()]
  def pickup_status_for_household(household_id) when is_binary(household_id) do
    order_line_ids = OrderSource.order_line_ids_for_household(household_id)

    if order_line_ids == [] do
      []
    else
      read(fn ->
        Repo.all(
          from f in Fulfillment,
            where: f.order_line_id in ^order_line_ids,
            order_by: [desc: f.inserted_at],
            preload: [variant: :product]
        )
      end)
    end
  end

  ## Availabilty labels (portal)

  @doc "The portal availability label for a variant, never exposing counts."
  @spec availability_label(ProductVariant.t(), StockLevel.t() | nil) :: String.t()
  def availability_label(%ProductVariant{} = variant, level) do
    do_availability_label(available_for(level), variant.low_stock_threshold)
  end

  @doc "The aggregated portal availability label for a product."
  @spec product_availability_label(binary()) :: String.t()
  def product_availability_label(product_id) do
    read(fn ->
      rows =
        Repo.all(
          from v in ProductVariant,
            left_join: s in StockLevel,
            on: s.variant_id == v.id and is_nil(s.venue_id),
            where: v.product_id == ^product_id and v.active == true,
            select: %{
              on_hand: coalesce(s.on_hand, 0),
              reserved: coalesce(s.reserved, 0),
              threshold: v.low_stock_threshold
            }
        )

      labels = Enum.map(rows, &do_availability_label(&1.on_hand - &1.reserved, &1.threshold))
      aggregate_label(labels)
    end)
  end

  ## Image uploads (reuses the tenancy storage behaviour)

  @doc "Validates and presigns an inventory image upload."
  @spec presign_upload(Policy.actor(), map()) ::
          {:ok, Storage.presigned()} | {:error, term()}
  def presign_upload(_actor, attrs) do
    Storage.presign_put(attrs, TenantContext.get_tenant_id())
  end

  ## Private — product/variant insert helpers

  defp insert_variant(product_id, attrs) do
    attrs = attrs |> tenant_attrs() |> Map.put("product_id", product_id)

    %ProductVariant{}
    |> ProductVariant.changeset(attrs)
    |> Repo.insert()
  end

  defp reposition(schema, id, position) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> record |> Ecto.Changeset.change(position: position) |> Repo.update()
    end
  end

  ## Private — reservations

  defp do_reserve(order_id, lines) do
    variant_ids = Enum.map(lines, & &1.variant_id)
    ensure_levels(variant_ids)
    levels = lock_levels(variant_ids)
    already_reserved = reserved_variant_ids(order_id, :reserved)
    released = reserved_variant_ids(order_id, :released)

    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      case reserve_decision(order_id, line, levels, already_reserved, released) do
        :skip -> {:cont, {:ok, acc}}
        {:ok, movement} -> {:cont, {:ok, [movement | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reserve_decision(order_id, line, levels, already_reserved, released) do
    cond do
      MapSet.member?(already_reserved, line.variant_id) -> :skip
      MapSet.member?(released, line.variant_id) -> :skip
      true -> reserve_available(order_id, line, Map.fetch!(levels, line.variant_id))
    end
  end

  defp reserve_available(order_id, line, level) do
    available = StockLevel.available(level)

    if available >= line.quantity do
      reserve_line(order_id, line, level)
    else
      {:error, {:insufficient_stock, line.variant_id, available}}
    end
  end

  defp reserve_line(order_id, line, level) do
    with {:ok, movement} <-
           insert_movement(%{
             variant_id: line.variant_id,
             delta: line.quantity,
             kind: :reserved,
             order_id: order_id,
             note: line.note
           }),
         {:ok, _level} <-
           update_level(level, reserved: level.reserved + line.quantity) do
      {:ok, movement}
    end
  end

  ## Private — order lifecycle

  defp do_release_order(order_id) do
    active = active_reservations(order_id)

    ensure_levels(Enum.map(active, & &1.variant_id))
    levels = lock_levels(Enum.map(active, & &1.variant_id))

    Enum.reduce_while(active, {:ok, []}, fn reservation, {:ok, acc} ->
      level = Map.fetch!(levels, reservation.variant_id)

      with {:ok, movement} <-
             insert_movement(%{
               variant_id: reservation.variant_id,
               delta: -reservation.quantity,
               kind: :released,
               order_id: order_id
             }),
           {:ok, _level} <-
             update_level(level, reserved: level.reserved - reservation.quantity) do
        {:cont, {:ok, [movement | acc]}}
      else
        {:error, {:constraint, _}} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp do_convert_to_sold(order_id) do
    active = active_reservations(order_id)

    ensure_levels(Enum.map(active, & &1.variant_id))
    levels = lock_levels(Enum.map(active, & &1.variant_id))

    Enum.reduce_while(active, {:ok, []}, fn reservation, {:ok, acc} ->
      level = Map.fetch!(levels, reservation.variant_id)

      with {:ok, _sold} <-
             insert_movement(%{
               variant_id: reservation.variant_id,
               delta: -reservation.quantity,
               kind: :sold,
               order_id: order_id
             }),
           {:ok, _released} <-
             insert_movement(%{
               variant_id: reservation.variant_id,
               delta: -reservation.quantity,
               kind: :released,
               order_id: order_id
             }),
           {:ok, _level} <-
             update_level(level,
               on_hand: level.on_hand - reservation.quantity,
               reserved: level.reserved - reservation.quantity
             ) do
        {:cont,
         {:ok, [%{variant_id: reservation.variant_id, quantity: reservation.quantity} | acc]}}
      else
        {:error, {:constraint, _}} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp do_restock(actor, order_id, lines) do
    ensure_levels(Enum.map(lines, & &1.variant_id))
    levels = lock_levels(Enum.map(lines, & &1.variant_id))

    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      case restock_line(actor, order_id, line, Map.fetch!(levels, line.variant_id)) do
        :skip -> {:cont, {:ok, acc}}
        {:ok, movement} -> {:cont, {:ok, [movement | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restock_line(actor, order_id, line, level) do
    if restocked?(order_id, line.variant_id) do
      :skip
    else
      insert_restock(actor, order_id, line, level)
    end
  end

  defp restocked?(order_id, variant_id) do
    Repo.exists?(
      from m in StockMovement,
        where: m.order_id == ^order_id and m.variant_id == ^variant_id and m.kind == :returned
    )
  end

  defp insert_restock(actor, order_id, line, level) do
    {actor_type, actor_id} = actor_fields(actor)

    with {:ok, movement} <-
           insert_movement(%{
             variant_id: line.variant_id,
             delta: line.quantity,
             kind: :returned,
             order_id: order_id,
             actor_type: actor_type,
             actor_id: actor_id,
             note: fetch_attr(line, :note)
           }),
         {:ok, _level} <- update_level(level, on_hand: level.on_hand + line.quantity) do
      _ =
        Audit.record(actor, "inventory.stock.refund_restocked", movement, %{
          order_id: order_id,
          variant_id: line.variant_id,
          quantity: line.quantity
        })

      {:ok, movement}
    end
  end

  defp active_reservations(order_id) do
    rows =
      Repo.all(
        from m in StockMovement,
          where: m.order_id == ^order_id and m.kind in [:reserved, :released],
          select: %{variant_id: m.variant_id, delta: m.delta, kind: m.kind}
      )

    released = for r <- rows, r.kind == :released, into: %{}, do: {r.variant_id, -r.delta}

    for r <- rows, r.kind == :reserved, into: [] do
      case Map.get(released, r.variant_id) do
        nil -> %{variant_id: r.variant_id, quantity: r.delta}
        released_qty when released_qty >= r.delta -> nil
        released_qty -> %{variant_id: r.variant_id, quantity: r.delta - released_qty}
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.variant_id)
  end

  defp reserved_variant_ids(order_id, kind) do
    Repo.all(
      from m in StockMovement,
        where: m.order_id == ^order_id and m.kind == ^kind,
        select: m.variant_id
    )
    |> MapSet.new()
  end

  defp maybe_emit_low_stock(sold) do
    today = Date.utc_today()

    sold
    |> Enum.map(& &1.variant_id)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn variant_id, {:ok, acc} ->
      case maybe_emit_low_stock_for(variant_id, today) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, level} -> {:cont, {:ok, [level | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_emit_low_stock_for(variant_id, today) do
    variant = Repo.get(ProductVariant, variant_id)

    level =
      Repo.one(from s in StockLevel, where: s.variant_id == ^variant_id and is_nil(s.venue_id))

    cond do
      is_nil(variant) or is_nil(variant.low_stock_threshold) or is_nil(level) ->
        {:ok, nil}

      level.low_stock_notified_on == today ->
        {:ok, nil}

      StockLevel.available(level) > variant.low_stock_threshold ->
        {:ok, nil}

      true ->
        with {:ok, updated} <- update_level(level, low_stock_notified_on: today),
             {:ok, _job} <-
               Events.publish("stock.low", %{
                 variant_id: variant_id,
                 product_id: variant.product_id,
                 available: StockLevel.available(updated),
                 threshold: variant.low_stock_threshold,
                 tenant_id: variant.tenant_id
               }) do
          {:ok, updated}
        end
    end
  end

  defp do_create_fulfillments(_order_id, []), do: {:ok, []}

  defp do_create_fulfillments(_order_id, lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      attrs =
        %{
          order_line_id: line.order_line_id,
          variant_id: line.variant_id,
          pickup_venue_id: line.pickup_venue_id
        }
        |> tenant_attrs()

      %Fulfillment{}
      |> Fulfillment.changeset(attrs)
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:tenant_id, :order_line_id]
      )
      |> case do
        {:ok, fulfillment} -> {:cont, {:ok, [fulfillment | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  ## Private — stock levels

  defp ensure_level(variant_id) do
    ensure_levels([variant_id])

    case Repo.one(
           from s in StockLevel,
             where: s.variant_id == ^variant_id and is_nil(s.venue_id),
             limit: 1
         ) do
      nil -> {:error, :not_found}
      level -> {:ok, level}
    end
  end

  defp ensure_levels([]), do: :ok

  defp ensure_levels(variant_ids) do
    tenant_id = TenantContext.get_tenant_id()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      variant_ids
      |> Enum.uniq()
      |> Enum.map(fn variant_id ->
        %{
          id: UUIDv7.generate(),
          tenant_id: tenant_id,
          variant_id: variant_id,
          on_hand: 0,
          reserved: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(StockLevel, rows, on_conflict: :nothing)

    :ok
  end

  defp lock_levels(variant_ids) do
    variant_ids
    |> Enum.uniq()
    |> then(fn ids ->
      if ids == [] do
        []
      else
        Repo.all(
          from s in StockLevel,
            where: s.variant_id in ^ids and is_nil(s.venue_id),
            order_by: [asc: s.variant_id],
            lock: "FOR UPDATE"
        )
      end
    end)
    |> Map.new(&{&1.variant_id, &1})
  end

  defp update_level(level, changes) do
    level
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
  end

  defp insert_movement(attrs) do
    attrs
    |> tenant_attrs()
    |> then(&StockMovement.changeset(%StockMovement{}, &1))
    |> Repo.insert()
  end

  defp ledger_on_hand(variant_id) do
    Repo.one(
      from m in StockMovement,
        where: m.variant_id == ^variant_id and m.kind in ^StockMovement.non_reservation_kinds(),
        select: coalesce(sum(m.delta), 0)
    )
  end

  ## Private — receive/adjust

  defp do_receive(actor, variant_id, quantity, note) do
    with {:ok, _variant} <- fetch_variant(variant_id),
         {:ok, level} <- lock_or_create(variant_id) do
      {actor_type, actor_id} = actor_fields(actor)

      with {:ok, movement} <-
             insert_movement(%{
               variant_id: variant_id,
               delta: quantity,
               kind: :received,
               note: note,
               actor_type: actor_type,
               actor_id: actor_id
             }),
           {:ok, _level} <- update_level(level, on_hand: level.on_hand + quantity),
           {:ok, _audit} <-
             Audit.record(actor, "inventory.stock.received", movement, %{
               variant_id: variant_id,
               quantity: quantity
             }) do
        {:ok, movement}
      end
    end
  end

  defp do_adjust(actor, variant_id, delta, reason) do
    with {:ok, _variant} <- fetch_variant(variant_id),
         {:ok, level} <- lock_or_create(variant_id),
         :ok <- ensure_not_below_reserved(level, delta, variant_id) do
      apply_adjustment(actor, variant_id, delta, reason, level)
    end
  end

  defp ensure_not_below_reserved(level, delta, variant_id) do
    if level.on_hand + delta < level.reserved do
      {:error, {:stock_below_reserved, variant_id}}
    else
      :ok
    end
  end

  defp apply_adjustment(actor, variant_id, delta, reason, level) do
    {actor_type, actor_id} = actor_fields(actor)

    with {:ok, movement} <-
           insert_movement(%{
             variant_id: variant_id,
             delta: delta,
             kind: :adjusted,
             note: reason,
             actor_type: actor_type,
             actor_id: actor_id
           }),
         {:ok, _level} <- update_level(level, on_hand: level.on_hand + delta) do
      _ =
        Audit.record(actor, "inventory.stock.adjusted", movement, %{
          variant_id: variant_id,
          delta: delta,
          reason: reason
        })

      {:ok, movement}
    end
  end

  defp lock_or_create(variant_id) do
    ensure_levels([variant_id])

    case Repo.one(
           from s in StockLevel,
             where: s.variant_id == ^variant_id and is_nil(s.venue_id),
             lock: "FOR UPDATE"
         ) do
      nil -> {:error, :not_found}
      level -> {:ok, level}
    end
  end

  ## Private — availability

  defp do_availability_label(available, _threshold) when available <= 0,
    do: @availability_sold_out

  defp do_availability_label(available, threshold)
       when is_integer(threshold) and available <= threshold,
       do: @availability_low

  defp do_availability_label(_available, _threshold), do: @availability_in

  defp aggregate_label([]), do: @availability_sold_out

  defp aggregate_label(labels) do
    cond do
      Enum.all?(labels, &(&1 == @availability_sold_out)) -> @availability_sold_out
      Enum.any?(labels, &(&1 == @availability_low)) -> @availability_low
      true -> @availability_in
    end
  end

  defp available_for(nil), do: 0
  defp available_for(level), do: StockLevel.available(level)

  ## Private — shared helpers

  defp run_multi(multi, key) do
    # Prepending the GUC step ourselves sets it before the writes and preserves
    # the failed step's reason; see docs/rfcs for the core Multi clause bug.
    set_tenant =
      Multi.run(Multi.new(), :__set_tenant__, fn _repo, _changes ->
        Repo.set_tenant_guc(TenantContext.get_tenant_id())
        {:ok, :ok}
      end)

    multi = Multi.prepend(multi, set_tenant)

    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, Map.fetch!(changes, key)}
      {:error, ^key, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp run_multi_changes(multi) do
    set_tenant =
      Multi.run(Multi.new(), :__set_tenant__, fn _repo, _changes ->
        Repo.set_tenant_guc(TenantContext.get_tenant_id())
        {:ok, :ok}
      end)

    multi = Multi.prepend(multi, set_tenant)

    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, changes}
      {:error, _step, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp unwrap({:ok, result}), do: result
  defp unwrap({:error, reason}), do: {:error, reason}

  defp with_loaded(schema, id, fun) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> fun.(record)
    end
  end

  defp fetch_record(schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
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
      %Tenant{currency: currency} when is_binary(currency) ->
        currency

      _ ->
        case TenantContext.get_tenant_id() do
          nil -> "CAD"
          id -> Repo.get!(Tenant, id, skip_tenant: true).currency
        end
    end
  end

  defp tenant_attrs(attrs) do
    attrs
    |> Enum.into(%{})
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
    |> Map.drop(["tenant_id", "id"])
    |> Map.put("tenant_id", TenantContext.get_tenant_id())
  end

  defp normalize_line(line) do
    %{
      variant_id: fetch_attr(line, :variant_id),
      quantity: fetch_attr(line, :quantity) || 1,
      note: fetch_attr(line, :note)
    }
  end

  defp normalize_order_lines(nil), do: []

  defp normalize_order_lines(lines) when is_list(lines) do
    Enum.map(lines, fn line ->
      %{
        order_line_id: fetch_attr(line, :order_line_id),
        variant_id: fetch_attr(line, :variant_id),
        pickup_venue_id: fetch_attr(line, :pickup_venue_id)
      }
    end)
  end

  defp positive_quantity(attrs) do
    case fetch_attr(attrs, :quantity) do
      quantity when is_integer(quantity) and quantity > 0 -> {:ok, quantity}
      _ -> {:error, {:invalid_quantity, "Quantity must be a positive integer"}}
    end
  end

  defp signed_delta(attrs) do
    case fetch_attr(attrs, :delta) do
      delta when is_integer(delta) and delta != 0 -> {:ok, delta}
      _ -> {:error, {:invalid_delta, "Delta must be a non-zero integer"}}
    end
  end

  defp required_reason(attrs) do
    case fetch_attr(attrs, :reason) || fetch_attr(attrs, :note) do
      reason when is_binary(reason) and reason != "" -> {:ok, reason}
      _ -> {:error, {:reason_required, "A reason is required"}}
    end
  end

  defp actor_fields(nil), do: {nil, nil}
  defp actor_fields(%StaffActor{staff_user_id: id}), do: {"StaffActor", id}
  defp actor_fields(%CustomerActor{customer_user_id: id}), do: {"CustomerActor", id}
  defp actor_fields(_), do: {nil, nil}

  defp normalize_filters(filters), do: Enum.into(filters, %{})

  defp filter_value(filters, key), do: Map.get(filters, key) || Map.get(filters, to_string(key))

  defp fetch_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp where_active(query, filters) do
    case filter_value(filters, :active) do
      nil -> query
      value -> where(query, [r], r.active == ^value)
    end
  end

  defp where_visible(query, filters) do
    case filter_value(filters, :visible_in_portal) do
      nil -> query
      value -> where(query, [r], r.visible_in_portal == ^value)
    end
  end

  defp where_variant(query, filters) do
    case filter_value(filters, :variant_id) do
      nil -> query
      value -> where(query, [r], r.variant_id == ^value)
    end
  end

  defp where_status(query, filters) do
    case filter_value(filters, :status) do
      nil -> query
      value -> where(query, [r], r.status == ^value)
    end
  end

  defp where_order_line(query, filters) do
    case filter_value(filters, :order_line_id) do
      nil -> query
      value -> where(query, [r], r.order_line_id == ^value)
    end
  end
end
