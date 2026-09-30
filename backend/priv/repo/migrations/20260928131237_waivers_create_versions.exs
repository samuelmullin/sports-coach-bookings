defmodule SportsCoachBookings.Repo.Migrations.WaiversCreateVersions do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :waiver_versions do
      add :waiver_template_id,
          references(:waiver_templates, type: :uuid, on_delete: :delete_all),
          null: false

      add :version, :integer, null: false
      add :body_markdown, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :published_at, :utc_datetime_usec
      add :content_sha256, :string, null: false
    end

    create unique_index(:waiver_versions, [:waiver_template_id, :version])

    # At most one published version per template. Drafts and superseded
    # versions are unconstrained.
    create unique_index(:waiver_versions, [:waiver_template_id],
             where: "status = 'published'",
             name: :waiver_versions_one_published_per_template
           )

    execute(
      """
      CREATE OR REPLACE FUNCTION waivers_prevent_published_version_edit()
      RETURNS trigger AS $$
      BEGIN
        IF OLD.status IN ('published', 'superseded') THEN
          IF NEW.body_markdown IS DISTINCT FROM OLD.body_markdown
             OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
             OR NEW.version IS DISTINCT FROM OLD.version
             OR NEW.waiver_template_id IS DISTINCT FROM OLD.waiver_template_id THEN
            RAISE EXCEPTION 'waiver version % is immutable once published', OLD.id
              USING ERRCODE = 'check_violation';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS waivers_prevent_published_version_edit()"
    )

    execute(
      """
      CREATE TRIGGER waiver_versions_immutable
      BEFORE UPDATE ON waiver_versions
      FOR EACH ROW EXECUTE FUNCTION waivers_prevent_published_version_edit();
      """,
      "DROP TRIGGER IF EXISTS waiver_versions_immutable ON waiver_versions"
    )
  end
end
