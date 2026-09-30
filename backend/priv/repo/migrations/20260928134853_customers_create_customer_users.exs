defmodule SportsCoachBookings.Repo.Migrations.CustomersCreateCustomerUsers do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Customer identity is per tenant: the same email at two tenants is two
    # independent accounts. Tenant-owned (RLS enabled and forced).
    tenant_table :customer_users do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :phone, :string
      add :terms_version, :string
      add :terms_accepted_at, :utc_datetime_usec
      add :privacy_version, :string
      add :privacy_accepted_at, :utc_datetime_usec
      add :confirmed_at, :utc_datetime_usec
      add :active, :boolean, null: false, default: true
    end

    # `(tenant_id, lower(email))` via citext: email is case-insensitive within a
    # tenant but may repeat across tenants.
    create unique_index(:customer_users, [:tenant_id, :email])

    # Opaque, single-use tokens: sessions, email confirmation, password reset,
    # and email change. Tenant-owned (RLS).
    tenant_table :customer_users_tokens do
      add :token, :string, null: false
      add :context, :string, null: false
      add :sent_to, :string

      add :customer_user_id,
          references(:customer_users, type: :uuid, on_delete: :delete_all),
          null: false
    end

    create unique_index(:customer_users_tokens, [:tenant_id, :token])
    create index(:customer_users_tokens, [:customer_user_id])
    create index(:customer_users_tokens, [:customer_user_id, :context])
  end
end
