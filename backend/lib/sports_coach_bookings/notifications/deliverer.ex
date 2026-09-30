defmodule SportsCoachBookings.Notifications.Deliverer do
  @moduledoc """
  Injectable mail deliverer.

  The engine sends through this module so tests can substitute a failing
  deliverer (via `config :sports_coach_bookings, :notifications_deliverer`)
  without touching the real Swoosh mailer.
  """

  @callback deliver(Swoosh.Email.t()) :: {:ok, term()} | {:error, term()}

  @doc "Delivers `email` using the configured deliverer (Swoosh by default)."
  @spec deliver(Swoosh.Email.t()) :: {:ok, term()} | {:error, term()}
  def deliver(%Swoosh.Email{} = email) do
    impl().deliver(email)
  end

  defp impl do
    Application.get_env(
      :sports_coach_bookings,
      :notifications_deliverer,
      SportsCoachBookings.Notifications.Deliverer.Swoosh
    )
  end
end

defmodule SportsCoachBookings.Notifications.Deliverer.Swoosh do
  @moduledoc "The default deliverer: sends through `SportsCoachBookings.Mailer`."

  @behaviour SportsCoachBookings.Notifications.Deliverer

  @impl true
  def deliver(email), do: SportsCoachBookings.Mailer.deliver(email)
end
