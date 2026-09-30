defmodule SportsCoachBookings.Repo.Migrations.ReservationsCreateReservations do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :reservations do
      # SHA-256 of the opaque bearer token. The token itself is never stored.
      add :token_hash, :binary, null: false

      # Cross-context (Catalog), plain uuid, no FK.
      add :offering_id, :binary_id

      # Ecto enum: active | converted | expired | released.
      add :status, :string, null: false, default: "active"

      add :expires_at, :utc_datetime_usec, null: false
      add :last_activity_at, :utc_datetime_usec, null: false

      # Cross-context (Customers); set when the guest reserves converts after auth.
      add :household_id, :binary_id
      add :converted_at, :utc_datetime_usec
    end

    # One bearer token identifies at most one reservation per tenant.
    create unique_index(:reservations, [:tenant_id, :token_hash])

    # Sweeper lookup: active reservations whose hold has lapsed.
    create index(:reservations, [:tenant_id, :status, :expires_at])
  end
end
