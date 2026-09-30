defmodule SportsCoachBookings.Commerce.PaymentEventsSubscriber do
  @moduledoc """
  Reacts to the Payments lifecycle events for Commerce orders. Owned by WP-13.

  Registered in `config :sports_coach_bookings, :event_subscribers` for
  `payment.succeeded`, `payment.failed`, and `payment.refunded`.

    * `payment.succeeded` — transitions the order to `paid` (guarded, once),
      records the discount redemption, and publishes `order.paid`.
    * `payment.failed` — expires the pending order and publishes `order.expired`,
      releasing reservations.
    * `payment.refunded` — reconciles the order's refunded total/status and
      publishes `order.refunded`.

  Delivery is at-least-once; every handler is idempotent (invariant 6: replaying
  a webhook never double-fulfils or double-charges).
  """

  @behaviour SportsCoachBookings.Events.Subscriber

  alias SportsCoachBookings.Commerce

  @impl true
  def handle_event("payment.succeeded", payload) do
    case {field(payload, "order_id"), field(payload, "payment_id")} do
      {order_id, _payment_id} when is_binary(order_id) ->
        Commerce.mark_order_paid(order_id, field(payload, "payment_id"))

      _ ->
        :ok
    end
  end

  def handle_event("payment.failed", payload) do
    case field(payload, "order_id") do
      order_id when is_binary(order_id) -> Commerce.expire_order(order_id)
      _ -> :ok
    end
  end

  def handle_event("payment.refunded", payload), do: Commerce.reconcile_refund(payload)

  def handle_event(_name, _payload), do: :ok

  defp field(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, safe_atom(key))
  end

  defp field(_payload, _key), do: nil

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :__missing__
  end
end
