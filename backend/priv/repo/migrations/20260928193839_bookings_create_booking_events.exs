defmodule SportsCoachBookings.Repo.Migrations.BookingsCreateBookingEvents do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :booking_events do
      add :booking_id,
          references(:bookings, type: :uuid, on_delete: :delete_all),
          null: false

      # Ecto enum: held | confirmed | cancelled | rebooked | attended | no_show |
      # provider_cancelled | hold_expired.
      add :kind, :string, null: false

      # Actor shape mirrors Core.Audit (`actor_type`/`actor_id`).
      add :actor_type, :string
      add :actor_id, :binary_id

      add :data, :map, null: false, default: %{}
    end

    # Append-only: no `updated_at`.
    alter table(:booking_events) do
      remove :updated_at, :utc_datetime_usec
    end

    create index(:booking_events, [:tenant_id, :booking_id, :inserted_at])

    execute(
      "REVOKE UPDATE, DELETE ON booking_events FROM scb_app",
      "GRANT UPDATE, DELETE ON booking_events TO scb_app"
    )
  end
end
