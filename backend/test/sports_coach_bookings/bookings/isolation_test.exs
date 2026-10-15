defmodule SportsCoachBookings.Bookings.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Bookings.BookingEvent
  alias SportsCoachBookings.Bookings.PrivateSessionRequest
  alias SportsCoachBookings.Bookings.SessionInvitation

  test "bookings are tenant-isolated" do
    assert_tenant_isolated(Booking, :booking)
  end

  test "booking_events are tenant-isolated" do
    assert_tenant_isolated(BookingEvent, :booking_event)
  end

  test "session invitations are tenant-isolated" do
    assert_tenant_isolated(SessionInvitation, :session_invitation)
  end

  test "private session requests are tenant-isolated" do
    assert_tenant_isolated(PrivateSessionRequest, :private_session_request)
  end
end
