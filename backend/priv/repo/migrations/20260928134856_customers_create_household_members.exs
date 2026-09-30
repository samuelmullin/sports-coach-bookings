defmodule SportsCoachBookings.Repo.Migrations.CustomersCreateHouseholdMembers do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Links a customer user to a household with a role. Tenant-owned (RLS).
    tenant_table :household_members do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false

      add :customer_user_id, references(:customer_users, type: :uuid, on_delete: :delete_all),
        null: false

      add :role, :string, null: false
      add :relationship, :string
    end

    create unique_index(:household_members, [:household_id, :customer_user_id])
    # One household per customer user in MVP: a customer user may belong to at
    # most one household within a tenant.
    create unique_index(:household_members, [:tenant_id, :customer_user_id])
    create index(:household_members, [:household_id])
    create index(:household_members, [:customer_user_id])
  end
end
