defmodule SportsCoachBookingsWeb.InventoryJSON do
  @moduledoc "Serialises inventory resources for the staff and portal APIs."

  alias SportsCoachBookings.Inventory.Fulfillment
  alias SportsCoachBookings.Inventory.Product
  alias SportsCoachBookings.Inventory.ProductVariant
  alias SportsCoachBookings.Inventory.StockLevel
  alias SportsCoachBookings.Inventory.StockMovement
  alias SportsCoachBookings.Tenancy.Storage

  @doc "Serialises a staff product."
  @spec product(Product.t()) :: map()
  def product(product) do
    %{
      id: product.id,
      name: product.name,
      description: product.description,
      image_keys: product.image_keys || [],
      image_urls: Enum.map(product.image_keys || [], &Storage.public_url/1),
      taxable: product.taxable,
      active: product.active,
      visible_in_portal: product.visible_in_portal,
      position: product.position,
      inserted_at: datetime(product.inserted_at),
      updated_at: datetime(product.updated_at)
    }
  end

  @doc "Serialises a product for the public portal (availability label only)."
  @spec public_product(Product.t(), String.t()) :: map()
  def public_product(product, availability) do
    %{
      id: product.id,
      name: product.name,
      description: product.description,
      image_urls: Enum.map(product.image_keys || [], &Storage.public_url/1),
      availability: availability
    }
  end

  @doc "Serialises a variant for the staff API (exact stock is included)."
  @spec variant(ProductVariant.t()) :: map()
  def variant(variant) do
    %{
      id: variant.id,
      product_id: variant.product_id,
      sku: variant.sku,
      option_values: variant.option_values || %{},
      price: variant.price,
      low_stock_threshold: variant.low_stock_threshold,
      active: variant.active,
      inserted_at: datetime(variant.inserted_at),
      updated_at: datetime(variant.updated_at)
    }
  end

  @doc "Serialises a variant for the public portal (availability label only)."
  @spec public_variant(ProductVariant.t(), String.t()) :: map()
  def public_variant(variant, availability) do
    %{
      id: variant.id,
      sku: variant.sku,
      option_values: variant.option_values || %{},
      price: variant.price,
      availability: availability
    }
  end

  @doc "Serialises a stock level (staff only; exposes counts)."
  @spec stock_level(StockLevel.t()) :: map()
  def stock_level(level) do
    %{
      id: level.id,
      variant_id: level.variant_id,
      on_hand: level.on_hand,
      reserved: level.reserved,
      available: StockLevel.available(level),
      venue_id: level.venue_id,
      inserted_at: datetime(level.inserted_at),
      updated_at: datetime(level.updated_at)
    }
  end

  @doc "Serialises a stock movement."
  @spec movement(StockMovement.t()) :: map()
  def movement(movement) do
    %{
      id: movement.id,
      variant_id: movement.variant_id,
      delta: movement.delta,
      kind: movement.kind,
      order_id: movement.order_id,
      actor_type: movement.actor_type,
      actor_id: movement.actor_id,
      note: movement.note,
      inserted_at: datetime(movement.inserted_at)
    }
  end

  @doc "Serialises a fulfillment."
  @spec fulfillment(Fulfillment.t()) :: map()
  def fulfillment(fulfillment) do
    %{
      id: fulfillment.id,
      order_line_id: fulfillment.order_line_id,
      variant_id: fulfillment.variant_id,
      status: fulfillment.status,
      pickup_venue_id: fulfillment.pickup_venue_id,
      picked_up_at: datetime(fulfillment.picked_up_at),
      picked_up_by: fulfillment.picked_up_by,
      inserted_at: datetime(fulfillment.inserted_at),
      updated_at: datetime(fulfillment.updated_at)
    }
  end

  @doc "Serialises a fulfillment for a customer's own pickup list."
  @spec pickup(Fulfillment.t()) :: map()
  def pickup(fulfillment) do
    %{
      id: fulfillment.id,
      order_line_id: fulfillment.order_line_id,
      status: fulfillment.status,
      product_name: product_name(fulfillment),
      option_values: option_values(fulfillment),
      pickup_venue_id: fulfillment.pickup_venue_id,
      picked_up_at: datetime(fulfillment.picked_up_at),
      inserted_at: datetime(fulfillment.inserted_at)
    }
  end

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp product_name(%{variant: %{product: %{name: name}}}), do: name
  defp product_name(_), do: nil

  defp option_values(%{variant: %{option_values: values}}), do: values || %{}
  defp option_values(_), do: %{}

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
