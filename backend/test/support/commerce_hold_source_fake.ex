defmodule SportsCoachBookings.Commerce.BookingHoldSource.Fake do
  @moduledoc """
  A test double for `SportsCoachBookings.Commerce.BookingHoldSource`.

  Holds are registered with `put_hold/2` (per test process) and resolved by
  `fetch_hold/1`. Used until wp-14's Bookings context is merged.
  """

  @behaviour SportsCoachBookings.Commerce.BookingHoldSource

  @doc "Registers a hold for the current test process."
  @spec put_hold(binary(), map()) :: :ok
  def put_hold(hold_id, attrs) when is_binary(hold_id) and is_map(attrs) do
    holds = Process.get(:commerce_fake_holds, %{})
    Process.put(:commerce_fake_holds, Map.put(holds, hold_id, attrs))
    :ok
  end

  @doc "Registers a hold with sensible defaults."
  @spec put_offering_hold(binary(), keyword()) :: :ok
  def put_offering_hold(hold_id, opts \\ []) do
    put_hold(hold_id, %{
      booking_id: opts[:booking_id] || Ecto.UUID.generate(),
      household_id: Keyword.fetch!(opts, :household_id),
      offering_id: Keyword.fetch!(opts, :offering_id),
      description: opts[:description] || "Drop-in session",
      unit_price: opts[:unit_price] || 1_000,
      taxable: opts[:taxable] || false
    })
  end

  @impl true
  def fetch_hold(hold_id) do
    case Process.get(:commerce_fake_holds, %{}) |> Map.get(hold_id) do
      nil -> {:error, :not_found}
      hold -> {:ok, hold}
    end
  end
end
