defmodule SportsCoachBookings.Commerce.OrderExpiryWorker do
  @moduledoc """
  Expires one unpaid order when its 30-minute payment window lapses.

  Scheduled at checkout with the order's `expires_at`; on run it expires the
  order only if it is still `pending_payment`, publishing `order.expired` (which
  releases inventory reservations and, via wp-14, booking holds). Idempotent:
  a replay of a paid or already-expired order is a no-op.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :default, max_attempts: 5

  alias SportsCoachBookings.Commerce

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: %{"order_id" => order_id}}) do
    case Commerce.expire_order(order_id) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
