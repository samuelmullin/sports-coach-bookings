defmodule SportsCoachBookings.Events.Subscriber do
  @moduledoc """
  Behaviour for domain-event subscribers.

  Register implementations in `config :sports_coach_bookings, :event_subscribers`,
  keyed by event name (see the event catalog in `00-shared-context.md`).
  Subscribers must be idempotent.
  """

  @callback handle_event(name :: String.t(), payload :: map()) ::
              :ok | {:ok, term()} | {:error, term()}
end
