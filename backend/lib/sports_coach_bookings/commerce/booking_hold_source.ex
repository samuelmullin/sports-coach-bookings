defmodule SportsCoachBookings.Commerce.BookingHoldSource do
  @moduledoc """
  Read seam from Commerce to the held bookings owned by Bookings.

  A drop-in cart line references a booking **hold** created by
  `Bookings.create_hold/…`. Commerce may not read the bookings tables, so it
  resolves the hold through the module configured at
  `config :sports_coach_bookings, :commerce_booking_hold_source`.

  The default implementation is `SportsCoachBookings.Bookings.HoldSource`
  (also set explicitly in `config/config.exs`); tests swap in fakes via the
  same config key.

  See `SportsCoachBookings.Commerce.add_drop_in/2`.
  """

  @type hold :: %{
          booking_id: binary(),
          household_id: binary(),
          offering_id: binary(),
          description: String.t() | nil,
          unit_price: non_neg_integer(),
          taxable: boolean()
        }

  @callback fetch_hold(hold_id :: binary()) :: {:ok, hold()} | {:error, :not_found}

  @doc "The configured hold source implementation."
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :sports_coach_bookings,
      :commerce_booking_hold_source,
      SportsCoachBookings.Bookings.HoldSource
    )
  end

  @doc "Resolves a booking hold, or `{:error, :not_found}`."
  @spec fetch_hold(binary()) :: {:ok, hold()} | {:error, :not_found}
  def fetch_hold(hold_id) when is_binary(hold_id), do: impl().fetch_hold(hold_id)
end
