defmodule SportsCoachBookings.Tenancy.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Tenancy.Branding

  test "branding is tenant-isolated" do
    assert_tenant_isolated(Branding, :branding)
  end
end
