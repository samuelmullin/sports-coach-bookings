defmodule SportsCoachBookings.Repo.Migrations.CoreRlsNullifEmptyGuc do
  @moduledoc """
  Hardens every tenant-isolation RLS policy against an empty-string GUC.

  Postgres exposes a custom parameter that was set and then reverted as `''`
  rather than NULL. `''::uuid` raises, so the policies now use
  `NULLIF(current_setting('app.tenant_id', true), '')::uuid`, which yields NULL
  (and therefore no matching rows) instead of erroring.
  """

  use Ecto.Migration

  @using "(tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)"
  @with_check "(tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)"
  @old "(tenant_id = current_setting('app.tenant_id', true)::uuid)"

  def up, do: alter_policies(@using, @with_check)
  def down, do: alter_policies(@old, @old)

  defp alter_policies(using, with_check) do
    execute("""
    DO $$
    DECLARE r record;
    BEGIN
      FOR r IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE policyname LIKE '%_tenant_isolation'
      LOOP
        EXECUTE format($fmt$
          ALTER POLICY %I ON %I.%I USING #{using} WITH CHECK #{with_check}
        $fmt$, r.policyname, r.schemaname, r.tablename);
      END LOOP;
    END
    $$;
    """)
  end
end
