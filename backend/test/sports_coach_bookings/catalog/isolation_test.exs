defmodule SportsCoachBookings.Catalog.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Catalog.{Discount, Offering, Package, TaxRate, Venue}

  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.TenantIsolation

  test "venues are tenant-isolated" do
    assert_tenant_isolated(Venue, :venue)
  end

  test "offerings are tenant-isolated" do
    assert_tenant_isolated(Offering, :offering)
  end

  test "packages are tenant-isolated" do
    assert_tenant_isolated(Package, :package)
  end

  test "discounts are tenant-isolated" do
    assert_tenant_isolated(Discount, :discount)
  end

  test "tax rates are tenant-isolated" do
    assert_tenant_isolated(TaxRate, :tax_rate)
  end

  test "package_offerings are tenant-isolated" do
    assert_join_isolated(:package_offering, fn tenant ->
      package = insert(:package, tenant_id: tenant.id)
      offering = insert(:offering, tenant_id: tenant.id)

      insert(:package_offering,
        tenant_id: tenant.id,
        package_id: package.id,
        offering_id: offering.id
      )
    end)
  end

  test "discount_targets are tenant-isolated" do
    assert_join_isolated(:discount_target, fn tenant ->
      discount = insert(:discount, tenant_id: tenant.id)
      offering = insert(:offering, tenant_id: tenant.id)

      insert(:discount_target,
        tenant_id: tenant.id,
        discount_id: discount.id,
        target_type: :offering,
        target_id: offering.id
      )
    end)
  end

  test "discount_redemptions are tenant-isolated" do
    assert_join_isolated(:discount_redemption, fn tenant ->
      discount = insert(:discount, tenant_id: tenant.id)

      insert(:discount_redemption,
        tenant_id: tenant.id,
        discount_id: discount.id,
        household_id: Ecto.UUID.generate(),
        order_id: Ecto.UUID.generate()
      )
    end)
  end

  defp assert_join_isolated(_factory, build_fun) do
    tenant_a = insert(:tenant)
    tenant_b = insert(:tenant)

    put_tenant(tenant_a)
    record = build_fun.(tenant_a)

    put_tenant(tenant_b)

    schema = record.__struct__
    table = schema.__schema__(:source)

    assert is_nil(Repo.get(schema, record.id)), "tenant B could read tenant A's #{table}"
    assert TenantIsolation.raw_count(table, record.id) == 0, "RLS leak on #{table}"
  end
end
