defmodule SportsCoachBookings.Inventory.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Inventory.Fulfillment
  alias SportsCoachBookings.Inventory.Product
  alias SportsCoachBookings.Inventory.ProductVariant
  alias SportsCoachBookings.Inventory.StockLevel
  alias SportsCoachBookings.Inventory.StockMovement

  test "products are tenant-isolated" do
    assert_tenant_isolated(Product, :product)
  end

  test "product_variants are tenant-isolated" do
    assert_tenant_isolated(ProductVariant, :product_variant)
  end

  test "stock_levels are tenant-isolated" do
    assert_tenant_isolated(StockLevel, :stock_level)
  end

  test "stock_movements are tenant-isolated" do
    assert_tenant_isolated(StockMovement, :stock_movement)
  end

  test "fulfillments are tenant-isolated" do
    assert_tenant_isolated(Fulfillment, :fulfillment)
  end
end
