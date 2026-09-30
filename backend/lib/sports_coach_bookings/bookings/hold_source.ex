defmodule SportsCoachBookings.Bookings.HoldSource do
  @moduledoc """
  Implements the Commerce read seam for booking holds (wp-13).

  `SportsCoachBookings.Commerce.add_drop_in/1` resolves a held booking through
  this module (configured at `:commerce_booking_hold_source`). A hold resolves
  only while the booking is `held`; its offering supplies the drop-in price,
  taxability, and description.
  """

  @behaviour SportsCoachBookings.Commerce.BookingHoldSource

  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling

  @impl true
  def fetch_hold(hold_id) when is_binary(hold_id) do
    case Repo.with_tenant_tx(fn -> Repo.get(Booking, hold_id) end) do
      {:ok, %Booking{status: :held} = booking} -> build_hold(booking)
      _ -> {:error, :not_found}
    end
  end

  defp build_hold(booking) do
    with {:ok, session} <- Scheduling.fetch_session(booking.session_id),
         {:ok, offering} <- Catalog.fetch_offering(session.offering_id) do
      {:ok,
       %{
         booking_id: booking.id,
         household_id: booking.household_id,
         offering_id: offering.id,
         description: offering.name,
         unit_price: offering.drop_in_price || 0,
         taxable: offering.taxable == true
       }}
    else
      _ -> {:error, :not_found}
    end
  end
end
