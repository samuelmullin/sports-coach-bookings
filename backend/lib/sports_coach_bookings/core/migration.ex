defmodule SportsCoachBookings.Core.Migration do
  @moduledoc """
  Helpers for tenant-owned migrations.

  `tenant_table/3` creates a table with a UUID primary key, a `tenant_id`
  foreign key, a `(tenant_id)` index, and Row Level Security enabled *and*
  forced with an isolation policy. Every tenant-owned table must be created
  with it (or an equivalent explicit RLS setup).

  Timeline columns default to `utc_datetime_usec`.

      use Ecto.Migration
      import SportsCoachBookings.Core.Migration

      def change do
        tenant_table :widgets do
          add :name, :string, null: false
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import SportsCoachBookings.Core.Migration
    end
  end

  defmacro tenant_table(name, opts \\ [], do: block) do
    table_opts = Keyword.take(opts, [:comment, :prefix, :engine, :options])
    tenant_id? = Keyword.get(opts, :tenant_id, true)

    quote do
      create table(unquote(name), [primary_key: false] ++ unquote(table_opts)) do
        add :id, :uuid, primary_key: true
        unquote(block)

        if unquote(tenant_id?) do
          add :tenant_id, references(:tenants, type: :uuid, on_delete: :delete_all), null: false
        end

        timestamps(type: :utc_datetime_usec)
      end

      if unquote(tenant_id?) do
        create index(unquote(name), [:tenant_id])

        execute("ALTER TABLE #{unquote(name)} ENABLE ROW LEVEL SECURITY")
        execute("ALTER TABLE #{unquote(name)} FORCE ROW LEVEL SECURITY")

        execute("""
        CREATE POLICY #{unquote(name)}_tenant_isolation ON #{unquote(name)}
          USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
          WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        """)
      end
    end
  end
end
