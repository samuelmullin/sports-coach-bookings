defmodule SportsCoachBookings.Customers.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Customers.{
    CustomerUser,
    CustomerUserToken,
    Household,
    HouseholdInvite,
    HouseholdMember
  }

  test "customer users are tenant-isolated" do
    assert_tenant_isolated(CustomerUser, :customer_user)
  end

  test "customer user tokens are tenant-isolated" do
    assert_tenant_isolated(CustomerUserToken, :customer_user_token)
  end

  test "households are tenant-isolated" do
    assert_tenant_isolated(Household, :household)
  end

  test "household members are tenant-isolated" do
    assert_tenant_isolated(HouseholdMember, :household_member)
  end

  test "household invites are tenant-isolated" do
    assert_tenant_isolated(HouseholdInvite, :household_invite)
  end
end
