defmodule SportsCoachBookings.Repo.Migrations.CustomersCreateHouseholds do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # A household groups the players a family manages. One per customer user in
    # MVP. Tenant-owned (RLS enabled and forced).
    tenant_table :households do
      add :name, :string
    end

    create index(:households, [:tenant_id, :inserted_at])
  end
end
