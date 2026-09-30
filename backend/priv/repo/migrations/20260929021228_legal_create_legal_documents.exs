defmodule SportsCoachBookings.Repo.Migrations.LegalCreateLegalDocuments do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :legal_documents do
      # `kind` is `terms` | `privacy` today but is intentionally a free string
      # so new document kinds (e.g. `cookies`) need no migration.
      add :kind, :string, null: false
      add :title, :string, null: false
      add :body_markdown, :text, null: false
      add :version, :integer, null: false
      add :active, :boolean, null: false, default: true
    end

    # Versions are unique per tenant and kind.
    create unique_index(:legal_documents, [:tenant_id, :kind, :version])

    # At most one active row per (tenant, kind); superseded versions are kept
    # with `active = false`.
    create unique_index(:legal_documents, [:tenant_id, :kind],
             where: "active",
             name: :legal_documents_one_active_per_kind
           )

    create index(:legal_documents, [:tenant_id, :kind, :active])
  end
end
