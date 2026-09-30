defmodule SportsCoachBookings.Repo.Migrations.CustomersCreateHouseholdInvites do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Pending invitations to co-manage a household. Tenant-owned (RLS). Only the
    # SHA-256 hash of the token is stored; the plaintext is what the invitee
    # receives and it is single-use with a 7-day expiry.
    tenant_table :household_invites do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false

      add :email, :citext, null: false
      add :relationship, :string
      add :token_hash, :string, null: false
      add :invited_by, references(:customer_users, type: :uuid, on_delete: :nilify_all)
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
    end

    create unique_index(:household_invites, [:tenant_id, :token_hash])
    create index(:household_invites, [:household_id])
    create index(:household_invites, [:tenant_id, :email])
  end
end
