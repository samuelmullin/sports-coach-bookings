defmodule SportsCoachBookings.Repo.Migrations.NotificationsCreateDeliveryRefs do
  use Ecto.Migration

  def change do
    # Platform table (no `tenant_id` RLS): maps a provider message id to the
    # owning tenant/delivery so an inbound webhook — which arrives with no tenant
    # context — can resolve the delivery without reading a tenant-owned table.
    create table(:notifications_delivery_refs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :provider_ref, :string, null: false
      add :tenant_id, :uuid, null: false
      add :delivery_id, :uuid, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notifications_delivery_refs, [:provider, :provider_ref])
  end
end
