defmodule SportsCoachBookings.Repo.Migrations.PoliciesCreateOfferingPolicyAssignments do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :offering_policy_assignments do
      # `offering_id` is a cross-context reference to Catalog.offerings; by
      # convention it is a plain uuid with no foreign key (see docs/erd.md).
      add :offering_id, :uuid, null: false

      add :cancellation_policy_id,
          references(:cancellation_policies, type: :uuid, on_delete: :delete_all),
          null: false
    end

    create unique_index(:offering_policy_assignments, [:offering_id])
  end
end
