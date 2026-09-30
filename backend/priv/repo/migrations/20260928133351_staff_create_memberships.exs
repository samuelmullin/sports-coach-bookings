defmodule SportsCoachBookings.Repo.Migrations.StaffCreateMemberships do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Links a global staff user to a tenant with a role. Tenant-owned: RLS is
    # enabled and forced by tenant_table/2.
    tenant_table :memberships do
      add :staff_user_id, references(:staff_users, type: :uuid, on_delete: :delete_all),
        null: false

      add :role, :string, null: false
      add :status, :string, null: false, default: "active"
      add :display_name, :string
      add :bio, :text
      add :photo_key, :string
    end

    create index(:memberships, [:staff_user_id])
    create unique_index(:memberships, [:tenant_id, :staff_user_id])

    # Cross-tenant self-read: `/api/platform/me` (the tenant picker) runs on the
    # platform host with no resolved tenant, so the caller's own memberships
    # must be readable when `app.staff_user_id` is set. This is additive to the
    # tenant-isolation policy created by tenant_table/2 (permissive policies are
    # OR-ed).
    execute("""
    CREATE POLICY memberships_self_read ON memberships
      FOR SELECT
      USING (
        staff_user_id = NULLIF(current_setting('app.staff_user_id', true), '')::uuid
      )
    """)
  end
end
