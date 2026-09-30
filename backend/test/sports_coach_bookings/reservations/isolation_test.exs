defmodule SportsCoachBookings.Reservations.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Reservations.Reservation
  alias SportsCoachBookings.Reservations.ReservationSession

  test "reservations are tenant-isolated" do
    assert_tenant_isolated(Reservation, :reservation)
  end

  test "reservation_sessions are tenant-isolated" do
    assert_tenant_isolated(ReservationSession, :reservation_session)
  end
end
