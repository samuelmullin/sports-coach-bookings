defmodule SportsCoachBookings.Repo.Migrations.PoliciesCreateCancellationPolicies do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :cancellation_policies do
      add :name, :string, null: false
      add :is_default, :boolean, null: false, default: false
      add :version, :integer, null: false, default: 1
      add :active, :boolean, null: false, default: true
      add :rules, :map, null: false
      add :customer_facing_summary, :text
    end

    # At most one default policy per tenant.
    create unique_index(:cancellation_policies, [:tenant_id],
             where: "is_default",
             name: :cancellation_policies_one_default_per_tenant
           )

    create index(:cancellation_policies, [:tenant_id, :active])
  end
end
