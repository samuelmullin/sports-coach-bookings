defmodule SportsCoachBookings.Waivers.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.TenantIsolation
  alias SportsCoachBookings.Waivers.WaiverTemplate

  test "waiver_templates are tenant-isolated" do
    assert_tenant_isolated(WaiverTemplate, :waiver_template)
  end

  test "waiver_template_offerings are tenant-isolated" do
    assert_child_isolated(:waiver_template_offering, fn tenant ->
      template = insert(:waiver_template, tenant_id: tenant.id)
      offering = insert(:offering, tenant_id: tenant.id)

      insert(:waiver_template_offering,
        tenant_id: tenant.id,
        waiver_template_id: template.id,
        offering_id: offering.id
      )
    end)
  end

  test "waiver_versions are tenant-isolated" do
    assert_child_isolated(:waiver_version, fn tenant ->
      template = insert(:waiver_template, tenant_id: tenant.id)
      insert(:waiver_version, tenant_id: tenant.id, waiver_template: template)
    end)
  end

  test "waiver_signatures are tenant-isolated" do
    assert_child_isolated(:waiver_signature, fn tenant ->
      version = insert(:waiver_version, tenant_id: tenant.id)
      insert(:waiver_signature, tenant_id: tenant.id, waiver_version: version)
    end)
  end

  defp assert_child_isolated(_factory, build_fun) do
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
