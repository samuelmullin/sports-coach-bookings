defmodule SportsCoachBookings.Repo.Migrations.CatalogCreateVenues do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :venues do
      add :name, :string, null: false
      add :address_line1, :string
      add :address_line2, :string
      add :city, :string
      add :province, :string
      add :postal_code, :string
      add :country, :string
      add :timezone, :string, null: false, default: "America/Toronto"
      add :notes, :text
      add :map_url, :string
      add :active, :boolean, null: false, default: true
    end

    create index(:venues, [:tenant_id, :active])
  end
end
