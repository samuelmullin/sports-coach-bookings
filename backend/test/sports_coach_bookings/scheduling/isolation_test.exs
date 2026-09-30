defmodule SportsCoachBookings.Scheduling.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Scheduling.Session
  alias SportsCoachBookings.Scheduling.SessionCoach
  alias SportsCoachBookings.Scheduling.SessionSeries

  test "sessions are tenant-isolated" do
    assert_tenant_isolated(Session, :session)
  end

  test "session_series are tenant-isolated" do
    assert_tenant_isolated(SessionSeries, :session_series)
  end

  test "session_coaches are tenant-isolated" do
    assert_tenant_isolated(SessionCoach, :session_coach)
  end
end
