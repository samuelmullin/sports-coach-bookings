defmodule SportsCoachBookings.Events.EventWorker do
  @moduledoc """
  Delivers a published domain event to its registered subscribers.

  Runs on the `:events` queue with tenant context restored. Delivery is
  at-least-once; subscribers must be idempotent.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :events

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events

  @impl true
  def perform_with_tenant(%Oban.Job{args: %{"name" => name, "payload" => payload}}) do
    payload = Map.put_new(payload, "tenant_id", TenantContext.get_tenant_id())

    results = Enum.map(Events.subscribers(name), &deliver(&1, name, payload))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  defp deliver(module, name, payload) do
    module.handle_event(name, payload)
  end
end
