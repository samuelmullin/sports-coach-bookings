defmodule SportsCoachBookings.Repo.Migrations.StaffCreateStaffUsers do
  use Ecto.Migration

  def change do
    # Global staff identity: one login shared across every tenant. Not
    # tenant-owned, so no tenant_id and no RLS policy.
    create table(:staff_users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:staff_users, [:email])

    create table(:staff_users_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :token, :string, null: false
      add :context, :string, null: false
      add :sent_to, :string

      add :staff_user_id, references(:staff_users, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:staff_users_tokens, [:token])
    create index(:staff_users_tokens, [:staff_user_id])
    create index(:staff_users_tokens, [:staff_user_id, :context])
  end
end
