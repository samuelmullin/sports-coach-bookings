defmodule SportsCoachBookings.Repo.Migrations.PaymentsCreateProviderAccounts do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # The tenant's connected provider account (Stripe Connect Express). One row
    # per (tenant, provider). Tenant-owned: RLS enabled and forced.
    tenant_table :provider_accounts do
      add :provider, :string, null: false
      add :account_ref, :string, null: false
      add :status, :string
      add :charges_enabled, :boolean, null: false, default: false
      add :payouts_enabled, :boolean, null: false, default: false
      add :requirements, :map, null: false, default: %{}

      # Platform fee in basis points (pending decision #1). Platform-controlled;
      # never editable through a tenant endpoint.
      add :platform_fee_bps, :integer, null: false, default: 0
    end

    create unique_index(:provider_accounts, [:tenant_id, :provider])
  end
end
