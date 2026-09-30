defmodule SportsCoachBookings.Repo.Migrations.StaffCreateStaffInvites do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Pending team invitations. Tenant-owned (RLS). The token is stored only as
    # a SHA-256 hash; the plaintext token is what the invitee receives.
    tenant_table :staff_invites do
      add :email, :citext, null: false
      add :role, :string, null: false
      add :token_hash, :string, null: false
      add :invited_by, :uuid
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
    end

    create unique_index(:staff_invites, [:tenant_id, :token_hash])
    create index(:staff_invites, [:tenant_id, :email])
  end
end
