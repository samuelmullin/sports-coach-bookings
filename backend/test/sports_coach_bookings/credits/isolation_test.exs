defmodule SportsCoachBookings.Credits.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Credits.CreditLedgerEntry
  alias SportsCoachBookings.Credits.CreditLot

  test "credit_lots are tenant-isolated" do
    assert_tenant_isolated(CreditLot, :credit_lot)
  end

  test "credit_ledger_entries are tenant-isolated" do
    assert_tenant_isolated(CreditLedgerEntry, :credit_ledger_entry)
  end
end
