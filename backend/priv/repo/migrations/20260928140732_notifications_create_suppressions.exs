defmodule SportsCoachBookings.Repo.Migrations.NotificationsCreateSuppressions do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Hard bounces and complaints; the address is skipped for every category
    # except password reset. Tenant-owned (RLS enabled and forced).
    tenant_table :suppressions do
      add :email, :citext, null: false
      add :reason, :string, null: false
    end

    create unique_index(:suppressions, [:tenant_id, :email])
  end
end
