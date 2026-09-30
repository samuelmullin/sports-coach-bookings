defmodule SportsCoachBookings.Staff.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Staff.{Membership, StaffInvite}

  test "memberships are tenant-isolated" do
    assert_tenant_isolated(Membership, :membership)
  end

  test "staff invites are tenant-isolated" do
    assert_tenant_isolated(StaffInvite, :staff_invite)
  end
end
