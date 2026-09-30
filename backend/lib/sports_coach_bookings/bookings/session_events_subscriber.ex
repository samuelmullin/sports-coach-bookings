defmodule SportsCoachBookings.Bookings.SessionEventsSubscriber do
  @moduledoc """
  Reacts to `session.cancelled` (cancel every booking with the provider-cancel
  outcome) and `session.rescheduled` (mark bookings free to change). Idempotent.
  """

  @behaviour SportsCoachBookings.Events.Subscriber

  alias SportsCoachBookings.Bookings

  # The context functions only return success per their specs; the fallback
  # clauses are defensive.
  @dialyzer {:nowarn_function, handle_event: 2}
  @impl true
  def handle_event("session.cancelled", %{"session_id" => session_id} = payload) do
    case Bookings.cancel_for_session(session_id, reason: payload["reason"] || "session cancelled") do
      :ok -> :ok
      other -> other
    end
  end

  def handle_event("session.rescheduled", %{"session_id" => session_id}) do
    case Bookings.set_free_change(session_id) do
      {:ok, _count} -> :ok
      other -> other
    end
  end

  def handle_event(_name, _payload), do: :ok
end
