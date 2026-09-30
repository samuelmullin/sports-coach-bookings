defmodule SportsCoachBookings.Inventory.OrderEventsSubscriber do
  @moduledoc """
  Reacts to the Commerce order lifecycle for physical goods. Owned by WP-08.

  Registered in `config :sports_coach_bookings, :event_subscribers` for
  `order.paid`, `order.expired`, `order.cancelled`, and `order.refunded`.

    * `order.paid` — converts reservations to sales, creates fulfillments, and
      emits `stock.low` when a variant falls to/below its threshold.
    * `order.expired` / `order.cancelled` — releases reservations.
    * `order.refunded` — does **not** restock automatically; an admin restocks
      explicitly via `Inventory.restock_refund/3`.

  Delivery is at-least-once, so every path is idempotent. Expected payloads are
  documented in `docs/rfcs/20260928-inventory-commerce-event-contract.md`.
  """

  @behaviour SportsCoachBookings.Events.Subscriber

  alias SportsCoachBookings.Inventory

  @impl true
  def handle_event("order.paid", payload) do
    with_order_id(payload, &Inventory.mark_order_paid(&1, lines(payload)))
  end

  def handle_event(event, payload) when event in ["order.expired", "order.cancelled"] do
    with_order_id(payload, &Inventory.release_order/1)
  end

  def handle_event("order.refunded", _payload), do: :ok

  def handle_event(_name, _payload), do: :ok

  defp with_order_id(payload, fun) do
    case order_id(payload) do
      nil ->
        {:error, :missing_order_id}

      order_id ->
        case fun.(order_id) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp order_id(payload), do: Map.get(payload, "order_id") || Map.get(payload, :order_id)

  defp lines(payload), do: Map.get(payload, "lines") || Map.get(payload, :lines)
end
