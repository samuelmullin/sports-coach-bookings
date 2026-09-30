defmodule SportsCoachBookings.Payments.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Payments.{Payment, ProviderAccount, Refund}

  test "provider_accounts are tenant-isolated" do
    assert_tenant_isolated(ProviderAccount, :provider_account)
  end

  test "payments are tenant-isolated" do
    assert_tenant_isolated(Payment, :payment)
  end

  test "refunds are tenant-isolated" do
    assert_tenant_isolated(Refund, :refund)
  end
end
