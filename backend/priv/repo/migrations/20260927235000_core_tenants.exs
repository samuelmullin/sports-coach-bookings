defmodule SportsCoachBookings.Repo.Migrations.CoreTenants do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext")

    create table(:tenants, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :slug, :citext, null: false
      add :status, :string, null: false, default: "active"
      add :timezone, :string, null: false, default: "America/Toronto"
      add :currency, :string, null: false, default: "CAD"
      add :contact_email, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:slug])

    create table(:tenant_domains, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenants, type: :uuid, on_delete: :delete_all), null: false
      add :host, :citext, null: false
      add :primary, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenant_domains, [:host])
    create index(:tenant_domains, [:tenant_id])

    create table(:audit_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenants, type: :uuid, on_delete: :delete_all), null: false
      add :actor_type, :string
      add :actor_id, :uuid
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :uuid
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_events, [:tenant_id])
    create index(:audit_events, [:resource_type, :resource_id])
    create index(:audit_events, [:action])

    execute("ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE audit_events FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY audit_events_tenant_isolation ON audit_events
      USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
      WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)
    """)
  end
end
