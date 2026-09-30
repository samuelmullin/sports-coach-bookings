defmodule SportsCoachBookings.Commerce.BookingHoldSource do
  @moduledoc """
  Read seam from Commerce to the held bookings owned by WP-14 (Bookings).

  A drop-in cart line references a booking **hold** created by
  `Bookings.create_hold/…`. Commerce may not read the bookings tables, so it
  resolves the hold through the module configured at
  `config :sports_coach_bookings, :commerce_booking_hold_source`.

  The default implementation, `SportsCoachBookings.Commerce.BookingHoldSource.Stub`,
  returns `{:error, :not_found}` until WP-14 lands. WP-14 implements the
  behaviour and points the config at its own module.

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
      __MODULE__.Stub
    )
  end

  @doc "Resolves a booking hold, or `{:error, :not_found}`."
  @spec fetch_hold(binary()) :: {:ok, hold()} | {:error, :not_found}
  def fetch_hold(hold_id) when is_binary(hold_id), do: impl().fetch_hold(hold_id)

  defmodule Stub do
    @moduledoc "Placeholder hold source used until Bookings (wp-14) is merged."

    @behaviour SportsCoachBookings.Commerce.BookingHoldSource

    @impl true
    def fetch_hold(_hold_id), do: {:error, :not_found}
  end
end
