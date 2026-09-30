defmodule SportsCoachBookings.Repo.Migrations.WaiversCreateTemplates do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :waiver_templates do
      add :name, :string, null: false
      add :scope, :string, null: false
      add :require_resign_on_new_version, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: true
    end

    create index(:waiver_templates, [:tenant_id, :active])

    tenant_table :waiver_template_offerings do
      add :waiver_template_id,
          references(:waiver_templates, type: :uuid, on_delete: :delete_all),
          null: false

      # `offering_id` is a cross-context reference to Catalog.offerings; by
      # convention it is a plain uuid with no foreign key (see docs/erd.md).
      add :offering_id, :uuid, null: false
    end

    create unique_index(:waiver_template_offerings, [:waiver_template_id, :offering_id])
  end
end
