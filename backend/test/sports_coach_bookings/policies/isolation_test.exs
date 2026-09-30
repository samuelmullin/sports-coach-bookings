defmodule SportsCoachBookings.Policies.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Policies.CancellationPolicy
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.TenantIsolation

  test "cancellation_policies are tenant-isolated" do
    assert_tenant_isolated(CancellationPolicy, :cancellation_policy)
  end

  test "offering_policy_assignments are tenant-isolated" do
    assert_child_isolated(fn tenant ->
      insert(:offering_policy_assignment,
        tenant_id: tenant.id,
        offering_id: Ecto.UUID.generate()
      )
    end)
  end

  defp assert_child_isolated(build_fun) do
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
