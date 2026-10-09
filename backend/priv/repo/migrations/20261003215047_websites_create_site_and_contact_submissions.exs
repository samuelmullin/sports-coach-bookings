defmodule SportsCoachBookings.Repo.Migrations.WebsitesCreateSiteAndContactSubmissions do
  use Ecto.Migration
  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :website_sites do
      add :enabled, :boolean, null: false, default: true
      add :draft_content, :map, null: false, default: %{}
      add :published_content, :map, null: false, default: %{}
      add :published_at, :utc_datetime_usec
    end

    create unique_index(:website_sites, [:tenant_id], name: :website_sites_tenant_unique_index)

    tenant_table :website_contact_submissions do
      add :name, :string, null: false
      add :email, :citext, null: false
      add :phone, :string
      add :company, :string
      add :subject, :string
      add :message, :text, null: false
      add :status, :string, null: false, default: "new"
      add :resolved_at, :utc_datetime_usec
    end

    create index(:website_contact_submissions, [:tenant_id, :status, :inserted_at])

    create constraint(:website_contact_submissions, :website_contact_submissions_status,
             check: "status IN ('new', 'read', 'resolved')"
           )
  end
end
