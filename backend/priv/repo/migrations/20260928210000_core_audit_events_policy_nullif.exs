defmodule SportsCoachBookings.Repo.Migrations.CoreAuditEventsPolicyNullif do
  use Ecto.Migration

  # WP-19: `audit_events` was created before `tenant_table/3` and its policy used
  # `current_setting('app.tenant_id', true)::uuid` directly. Once the GUC has
  # been set and rolled back on a pooled connection it resets to the empty
  # string, and `''::uuid` raises instead of returning no rows. Align it with
  # every other tenant-owned table (see `Core.Migration.tenant_table/3` and
  # docs/rfcs/20260928-core-rls-empty-tenant-guc.md).
  def up do
    execute("DROP POLICY IF EXISTS audit_events_tenant_isolation ON audit_events")

    execute("""
    CREATE POLICY audit_events_tenant_isolation ON audit_events
      USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
      WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS audit_events_tenant_isolation ON audit_events")

    execute("""
    CREATE POLICY audit_events_tenant_isolation ON audit_events
      USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
      WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)
    """)
  end
end
