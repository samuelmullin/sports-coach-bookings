defmodule SportsCoachBookings.Repo.Migrations.BookingsCreateBookings do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :bookings do
      # Cross-context (Scheduling), plain uuid, no FK.
      add :session_id, :binary_id, null: false
      # Cross-context (Players), plain uuid, no FK.
      add :player_id, :binary_id, null: false
      # Cross-context (Customers), plain uuid, no FK.
      add :household_id, :binary_id, null: false

      # Actor shape mirrors Core.Audit (`actor_type`/`actor_id`).
      add :booked_by_type, :string
      add :booked_by_id, :binary_id

      # Ecto enum: held | confirmed | cancelled | attended | no_show.
      add :status, :string, null: false, default: "held"
      # Ecto enum: credits | paid | comp.
      add :payment_method, :string, null: false

      add :credits_used, :integer, null: false, default: 0
      # Cross-context (Commerce), plain uuid, no FK.
      add :order_line_id, :binary_id

      # The policy snapshot used to compute cancellation outcomes later.
      add :policy_snapshot, :map, null: false, default: %{}

      add :rebook_count, :integer, null: false, default: 0

      add :rebooked_from_id,
          references(:bookings, type: :uuid, on_delete: :nilify_all)

      add :rebooked_to_id,
          references(:bookings, type: :uuid, on_delete: :nilify_all)

      add :hold_expires_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      # Set when a session is rescheduled: the booking may be changed for free.
      add :free_change_until, :utc_datetime_usec

      add :cancel_outcome, :map

      # Amount paid in minor units for `paid` bookings (implementation addition;
      # the policy engine needs it to compute partial refunds).
      add :paid_amount, :integer, null: false, default: 0
      add :currency, :string
    end

    create index(:bookings, [:tenant_id, :session_id])
    create index(:bookings, [:tenant_id, :player_id])
    create index(:bookings, [:tenant_id, :household_id, :inserted_at])
    create index(:bookings, [:tenant_id, :status])

    create index(:bookings, [:tenant_id, :hold_expires_at],
             where: "status = 'held'",
             name: :bookings_held_expiry
           )

    # One non-cancelled booking per (session, player).
    create unique_index(:bookings, [:tenant_id, :session_id, :player_id],
             where: "status <> 'cancelled'",
             name: :bookings_one_active_per_session_player
           )

    create constraint(:bookings, :bookings_credits_non_negative, check: "credits_used >= 0")
    create constraint(:bookings, :bookings_rebook_count_non_negative, check: "rebook_count >= 0")
  end
end
