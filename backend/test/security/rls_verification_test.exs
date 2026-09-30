defmodule SportsCoachBookings.Security.RlsVerificationTest do
  @moduledoc """
  WP-19: proves every tenant-owned table (one with a `tenant_id` column) has Row
  Level Security **enabled and forced** and at least one policy, that the
  application role cannot bypass RLS, and that the only tables carrying a
  `tenant_id` without RLS are the documented platform tables.
  """

  use SportsCoachBookings.DataCase, async: false

  # Platform tables that intentionally carry a `tenant_id` foreign key but no
  # RLS, because they are queried from a context with no tenant (host resolution
  # / provider webhooks). Justified in docs/security-review.md.
  @platform_tables_with_tenant_id ~w(tenant_domains notifications_delivery_refs)

  test "the application role is not a superuser and cannot bypass RLS" do
    %{rows: [[role, super, bypass]]} =
      Repo.query!(
        "SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user"
      )

    refute super, "#{role} is a superuser; RLS is bypassed"
    refute bypass, "#{role} has BYPASSRLS; RLS is bypassed"
  end

  test "every tenant-owned table has RLS enabled, forced, and a policy" do
    owned =
      tenant_tables()
      |> Enum.reject(&(&1.name in @platform_tables_with_tenant_id))

    refute owned == [], "no tenant-owned tables found; the query is wrong"

    policies = policies_by_table()

    for %{name: name, rls: rls, forced: forced} <- owned do
      assert rls, "#{name} does not have ROW LEVEL SECURITY enabled"
      assert forced, "#{name} does not have FORCE ROW LEVEL SECURITY"
      assert Map.get(policies, name, []) != [], "#{name} has no RLS policy"
    end
  end

  test "the allow-listed platform tables have no RLS policy" do
    names = tenant_tables() |> Enum.map(& &1.name)
    policies = policies_by_table()

    for name <- @platform_tables_with_tenant_id do
      assert name in names, "#{name} is allow-listed but does not exist"
      assert Map.get(policies, name, []) == [], "#{name} unexpectedly has an RLS policy"
    end
  end

  test "platform-only tables are tenant_id-free" do
    names = tenant_tables() |> Enum.map(& &1.name)

    refute "tenants" in names
    refute "webhook_events" in names
  end

  defp tenant_tables do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind = 'r'
        AND n.nspname = 'public'
        AND EXISTS (
          SELECT 1 FROM information_schema.columns col
          WHERE col.table_schema = 'public'
            AND col.table_name = c.relname
            AND col.column_name = 'tenant_id'
        )
      ORDER BY c.relname
      """)

    Enum.map(rows, fn [name, rls, forced] ->
      %{name: name, rls: rls, forced: forced}
    end)
  end

  defp policies_by_table do
    %{rows: rows} =
      Repo.query!("SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'")

    Enum.reduce(rows, %{}, fn [table, policy], acc ->
      Map.update(acc, table, [policy], &[policy | &1])
    end)
  end
end
