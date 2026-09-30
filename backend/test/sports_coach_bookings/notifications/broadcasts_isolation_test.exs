defmodule SportsCoachBookings.Notifications.BroadcastsIsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast
  alias SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient

  test "broadcasts are tenant-isolated" do
    assert_tenant_isolated(Broadcast, :broadcast)
  end

  test "broadcast recipients are tenant-isolated" do
    assert_tenant_isolated(BroadcastRecipient, :broadcast_recipient)
  end
end
