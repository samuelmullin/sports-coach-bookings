defmodule SportsCoachBookings.Repo.Migrations.CatalogAddBookingModesAndInvitations do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    alter table(:offerings) do
      add :public_enabled, :boolean, null: false, default: true
      add :public_max_players, :integer, null: false, default: 1
      add :public_players_per_coach, :integer, null: false, default: 1
      add :public_price_tiers, :map, null: false, default: %{}

      add :private_enabled, :boolean, null: false, default: false
      add :private_max_players, :integer, null: false, default: 1
      add :private_players_per_coach, :integer, null: false, default: 1
      add :private_price_tiers, :map, null: false, default: %{}

      add :allow_invite_reservations, :boolean, null: false, default: false
      add :invite_hold_hours, :integer, null: false, default: 48
      add :allow_private_conversion, :boolean, null: false, default: false
      add :allow_private_requests, :boolean, null: false, default: false
    end

    create constraint(:offerings, :offerings_public_max_players_positive,
             check: "public_max_players >= 1"
           )

    create constraint(:offerings, :offerings_private_max_players_positive,
             check: "private_max_players >= 1"
           )

    create constraint(:offerings, :offerings_public_ratio_positive,
             check: "public_players_per_coach >= 1"
           )

    create constraint(:offerings, :offerings_private_ratio_positive,
             check: "private_players_per_coach >= 1"
           )

    create constraint(:offerings, :offerings_invite_hold_hours_positive,
             check: "invite_hold_hours >= 1"
           )

    alter table(:sessions) do
      add :access_mode, :string, null: false, default: "public"
      add :party_size, :integer
      add :exclusive_household_id, :binary_id
    end

    create constraint(:sessions, :sessions_access_mode_valid,
             check: "access_mode IN ('public', 'private')"
           )

    create constraint(:sessions, :sessions_party_size_positive,
             check: "party_size IS NULL OR party_size >= 1"
           )

    create index(:sessions, [:tenant_id, :access_mode])
    create index(:sessions, [:tenant_id, :exclusive_household_id])

    tenant_table :session_invitations do
      add :session_id, :binary_id, null: false
      add :organizer_household_id, :binary_id, null: false
      add :invitee_household_id, :binary_id
      add :invitee_player_id, :binary_id
      add :email, :citext, null: false
      add :token_hash, :binary, null: false
      add :status, :string, null: false, default: "pending"
      add :payment_mode, :string, null: false
      add :seat_status, :string, null: false, default: "reserved"
      add :expires_at, :utc_datetime_usec
      add :accepted_at, :utc_datetime_usec
      add :declined_at, :utc_datetime_usec
      add :booking_id, :binary_id
    end

    create unique_index(:session_invitations, [:tenant_id, :token_hash])
    create index(:session_invitations, [:tenant_id, :session_id, :status])
    create index(:session_invitations, [:tenant_id, :organizer_household_id, :inserted_at])
    create index(:session_invitations, [:tenant_id, :invitee_household_id, :inserted_at])

    create constraint(:session_invitations, :session_invitations_status_valid,
             check: "status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled')"
           )

    create constraint(:session_invitations, :session_invitations_payment_mode_valid,
             check: "payment_mode IN ('split', 'organizer')"
           )

    create constraint(:session_invitations, :session_invitations_seat_status_valid,
             check: "seat_status IN ('reserved', 'purchased', 'released')"
           )

    alter table(:bookings) do
      modify :player_id, :binary_id, null: true, from: {:binary_id, null: false}
      add :session_invitation_id, :binary_id
      add :beneficiary_household_id, :binary_id
    end

    create index(:bookings, [:tenant_id, :session_invitation_id])
    create index(:bookings, [:tenant_id, :beneficiary_household_id])

    create constraint(:bookings, :bookings_player_or_invitation_required,
             check: "player_id IS NOT NULL OR session_invitation_id IS NOT NULL"
           )

    tenant_table :private_session_requests do
      add :offering_id, :binary_id, null: false
      add :household_id, :binary_id, null: false
      add :player_count, :integer, null: false
      add :preferred_times, {:array, :utc_datetime_usec}, null: false, default: []
      add :notes, :text
      add :status, :string, null: false, default: "pending"
      add :reviewed_by_id, :binary_id
      add :reviewed_at, :utc_datetime_usec
      add :session_id, :binary_id
      add :decline_reason, :text
    end

    create index(:private_session_requests, [:tenant_id, :status, :inserted_at])
    create index(:private_session_requests, [:tenant_id, :household_id, :inserted_at])

    create constraint(:private_session_requests, :private_session_requests_player_count_positive,
             check: "player_count >= 1"
           )

    create constraint(:private_session_requests, :private_session_requests_status_valid,
             check: "status IN ('pending', 'approved', 'declined', 'cancelled')"
           )

    execute(
      """
      UPDATE offerings
      SET public_max_players = default_capacity,
          public_players_per_coach = GREATEST(default_capacity, 1),
          private_enabled = (format = 'private'),
          private_max_players = default_capacity,
          private_players_per_coach = GREATEST(default_capacity, 1),
          public_enabled = (format <> 'private'),
          public_price_tiers = (
            SELECT jsonb_object_agg(n::text,
              jsonb_build_object('price', drop_in_price, 'credit_cost', credit_cost))
            FROM generate_series(1, default_capacity) AS n
          ),
          private_price_tiers = (
            SELECT jsonb_object_agg(n::text,
              jsonb_build_object('price', drop_in_price, 'credit_cost', credit_cost))
            FROM generate_series(1, default_capacity) AS n
          )
      """,
      "SELECT 1"
    )
  end
end
