defmodule SportsCoachBookings.Bookings.ExpiredHoldWorker do
  @moduledoc "Sweeps a single expired booking hold, releasing its seat. Idempotent."

  use SportsCoachBookings.Core.TenantWorker, queue: :default

  alias SportsCoachBookings.Bookings

  # `Bookings.expire_hold/1` only ever returns `{:ok, _}` per its spec; the
  # fallback clause is defensive.
  @dialyzer {:nowarn_function, perform_with_tenant: 1}
  @impl true
  def perform_with_tenant(%Oban.Job{args: %{"booking_id" => booking_id}}) do
    case Bookings.expire_hold(booking_id) do
      {:ok, _result} -> :ok
      other -> other
    end
  end
end
