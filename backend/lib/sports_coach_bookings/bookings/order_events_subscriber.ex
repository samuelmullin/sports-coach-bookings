defmodule SportsCoachBookings.Bookings.OrderEventsSubscriber do
  @moduledoc """
  Confirms held bookings when an order is paid and releases them when it
  expires. Idempotent (delivery is at-least-once).
  """

  @behaviour SportsCoachBookings.Events.Subscriber

  alias SportsCoachBookings.Bookings

  @impl true
  def handle_event("order.paid", %{"order_id" => order_id}) do
    Bookings.confirm_order_holds(order_id)
  end

  def handle_event("order.expired", %{"order_id" => order_id}) do
    Bookings.release_order_holds(order_id)
  end

  def handle_event(_name, _payload), do: :ok
end
