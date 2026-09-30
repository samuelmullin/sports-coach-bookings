defmodule SportsCoachBookings.Repo.Migrations.WaiversCreateSignatures do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :waiver_signatures do
      add :waiver_version_id,
          references(:waiver_versions, type: :uuid, on_delete: :delete_all),
          null: false

      # Cross-context references (Players + Customers); plain uuids, no FK.
      add :player_id, :uuid, null: false
      add :customer_user_id, :uuid, null: false

      add :signer_name_typed, :string, null: false
      add :signer_relationship, :string
      add :consent_checkbox, :boolean, null: false, default: false
      add :signed_at, :utc_datetime_usec, null: false
      add :ip, :inet, null: false
      add :user_agent, :text, null: false
      add :content_sha256, :string, null: false
      add :pdf_key, :string
    end

    create unique_index(:waiver_signatures, [:waiver_version_id, :player_id])
    create index(:waiver_signatures, [:tenant_id, :player_id])
    create index(:waiver_signatures, [:waiver_version_id])
  end
end
