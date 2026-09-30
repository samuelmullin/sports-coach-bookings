defmodule SportsCoachBookings.Repo.Migrations.FeedbackCreateRevisions do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :feedback_revisions do
      add :feedback_id,
          references(:session_feedback, type: :uuid, on_delete: :delete_all),
          null: false

      add :revision, :integer, null: false, default: 1
      add :body, :text, null: false
      add :skill_ratings, :map, null: false, default: %{}
      add :focus_next, :text
      add :visibility, :string, null: false
      add :shared_at, :utc_datetime_usec
      # Whether the edit asked wp-16 to notify the household of the change.
      add :notify, :boolean, null: false, default: false

      # Actor shape mirrors Core.Audit (`actor_type`/`actor_id`).
      add :editor_type, :string
      add :editor_id, :binary_id
    end

    # Append-only: no `updated_at`.
    alter table(:feedback_revisions) do
      remove :updated_at, :utc_datetime_usec
    end

    create index(:feedback_revisions, [:tenant_id, :feedback_id, :inserted_at])

    execute(
      "REVOKE UPDATE, DELETE ON feedback_revisions FROM scb_app",
      "GRANT UPDATE, DELETE ON feedback_revisions TO scb_app"
    )
  end
end
