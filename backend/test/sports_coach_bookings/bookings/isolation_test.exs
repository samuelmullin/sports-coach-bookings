defmodule SportsCoachBookings.Bookings.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Bookings.BookingEvent

  test "bookings are tenant-isolated" do
    assert_tenant_isolated(Booking, :booking)
  end

  test "booking_events are tenant-isolated" do
    assert_tenant_isolated(BookingEvent, :booking_event)
  end
end
