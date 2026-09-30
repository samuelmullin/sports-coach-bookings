defmodule SportsCoachBookings.Core.MoneyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.Money

  test "adds and subtracts in the same currency" do
    assert Money.add(Money.new(1000, "cad"), Money.new(250, "CAD")) |> Money.to_map() ==
             %{amount: 1250, currency: "CAD"}

    assert Money.subtract(Money.new(1000, "CAD"), Money.new(250, "CAD")) |> Money.to_map() ==
             %{amount: 750, currency: "CAD"}
  end

  test "refuses cross-currency arithmetic" do
    assert_raise ArgumentError, fn -> Money.add(Money.new(1, "CAD"), Money.new(1, "USD")) end
  end

  test "applies basis points with half-up rounding" do
    assert Money.apply_bps(Money.new(1000, "CAD"), 1500) |> Money.to_map() ==
             %{amount: 150, currency: "CAD"}

    assert Money.apply_bps(Money.new(5, "CAD"), 5000) |> Money.to_map() ==
             %{amount: 3, currency: "CAD"}
  end

  test "multiplies by an integer quantity" do
    assert Money.multiply(Money.new(1250, "CAD"), 3) |> Money.to_map() ==
             %{amount: 3750, currency: "CAD"}
  end

  test "formats to string" do
    assert Money.to_string(Money.new(1234, "CAD")) == "12.34 CAD"
    assert Money.to_string(Money.new(-5, "CAD")) == "-0.05 CAD"
  end
end
