defmodule SportsCoachBookings.Repo.Migrations.TenancyCreateBranding do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # One branding row per tenant. Tenant-owned (RLS).
    tenant_table :branding do
      add :logo_key, :string
      add :favicon_key, :string
      add :primary_color, :string
      add :secondary_color, :string
      add :accent_color, :string
      add :background_color, :string
      add :text_color, :string
      add :font_family, :string
      add :email_footer_text, :text
      add :social_links, :map, null: false, default: %{}
    end

    create unique_index(:branding, [:tenant_id], name: :branding_tenant_id_unique_index)
  end
end
