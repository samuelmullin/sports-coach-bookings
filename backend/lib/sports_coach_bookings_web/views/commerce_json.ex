defmodule SportsCoachBookingsWeb.CommerceJSON do
  @moduledoc "Serialises carts, orders, and order lines. Owned by WP-13."

  alias SportsCoachBookings.Commerce.Cart
  alias SportsCoachBookings.Commerce.CartLine
  alias SportsCoachBookings.Commerce.Order
  alias SportsCoachBookings.Commerce.OrderLine

  @doc "Serialises a cart, optionally with a pricing preview."
  @spec cart(Cart.t(), map() | nil) :: map()
  def cart(%Cart{} = cart, priced \\ nil) do
    %{
      id: cart.id,
      household_id: cart.household_id,
      discount_code: cart.discount_code,
      expires_at: datetime(cart.expires_at),
      lines: Enum.map(cart.lines || [], &cart_line/1),
      pricing: pricing(priced)
    }
  end

  @doc "Serialises a cart line."
  @spec cart_line(CartLine.t()) :: map()
  def cart_line(%CartLine{} = line) do
    %{
      id: line.id,
      cart_id: line.cart_id,
      type: line.type,
      ref_id: line.ref_id,
      quantity: line.quantity
    }
  end

  @doc "Serialises a pricing preview (`Commerce.price_cart/1`)."
  @spec pricing(map() | nil) :: map() | nil
  def pricing(nil), do: nil

  def pricing(priced) when is_map(priced) do
    %{
      lines: Enum.map(priced.lines, &priced_line/1),
      subtotal: priced.subtotal,
      discount_total: priced.discount_total,
      tax_total: priced.tax_total,
      total: priced.total
    }
  end

  defp priced_line(line) do
    %{
      type: line.type,
      ref_id: line.ref_id,
      description: Map.get(line, :description),
      unit_price: line.unit_price,
      quantity: line.quantity,
      amount: line.amount,
      discount_amount: line.discount_amount,
      tax_amount: line.tax_amount,
      line_total: line.line_total,
      taxable: line.taxable,
      available: Map.get(line, :available)
    }
  end

  @doc "Serialises a checkout result (`Commerce.checkout/3`)."
  @spec checkout(map()) :: map()
  def checkout(%{order: order, redirect_url: redirect_url}) do
    %{order: order(order), redirect_url: redirect_url}
  end

  @doc "Serialises an order and (when loaded) its lines."
  @spec order(Order.t()) :: map()
  def order(%Order{} = order) do
    %{
      id: order.id,
      number: order.number,
      household_id: order.household_id,
      status: order.status,
      currency: order.currency,
      subtotal: order.subtotal,
      discount_total: order.discount_total,
      tax_total: order.tax_total,
      total: order.total,
      refunded_total: order.refunded_total,
      discount_id: order.discount_id,
      payment_method: order.payment_method,
      payment_id: order.payment_id,
      expires_at: datetime(order.expires_at),
      paid_at: datetime(order.paid_at),
      inserted_at: datetime(order.inserted_at),
      lines: order_lines(order)
    }
  end

  @doc "Serialises an order line."
  @spec order_line(OrderLine.t()) :: map()
  def order_line(%OrderLine{} = line) do
    %{
      id: line.id,
      order_id: line.order_id,
      type: line.type,
      ref_id: line.ref_id,
      booking_id: line.booking_id,
      description: line.description,
      unit_price: line.unit_price,
      quantity: line.quantity,
      discount_amount: line.discount_amount,
      tax_amount: line.tax_amount,
      line_total: line.line_total,
      refunded_amount: line.refunded_amount,
      taxable: line.taxable
    }
  end

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp order_lines(%Order{lines: %Ecto.Association.NotLoaded{}}), do: []
  defp order_lines(%Order{lines: lines}) when is_list(lines), do: Enum.map(lines, &order_line/1)

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
