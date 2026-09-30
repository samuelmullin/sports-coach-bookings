defmodule SportsCoachBookings.Repo.Migrations.CreditsCreateCreditLedgerEntries do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :credit_ledger_entries do
      add :credit_lot_id,
          references(:credit_lots, type: :uuid, on_delete: :delete_all),
          null: false

      # Cross-context (Customers); plain uuid, no FK.
      add :household_id, :binary_id, null: false

      # Signed: positive for grant/reversal, negative for debit/expire.
      add :delta, :integer, null: false

      # Ecto enum: grant | debit | reversal | expire | adjust.
      add :reason, :string, null: false

      # Cross-context (Bookings); plain uuid, no FK. Also the consume/reverse
      # idempotency key (partial uniques below).
      add :booking_id, :binary_id

      # Self reference: a reversal points at the debit it reverses. Stored as a
      # plain uuid (no FK): the append-only table revokes UPDATE, and the
      # referential-integrity KEY SHARE lock a self-FK would take requires
      # UPDATE privilege.
      add :reverses_entry_id, :uuid, null: true

      # Actor shape mirrors Core.Audit (`actor_type`/`actor_id`).
      add :actor_type, :string
      add :actor_id, :binary_id
      add :note, :text
    end

    # Append-only ledger: no `updated_at`. `tenant_table/3` adds it, so drop it.
    alter table(:credit_ledger_entries) do
      remove :updated_at, :utc_datetime_usec
    end

    create index(:credit_ledger_entries, [:tenant_id, :household_id, :inserted_at])
    create index(:credit_ledger_entries, [:credit_lot_id])

    create index(:credit_ledger_entries, [:tenant_id, :booking_id],
             where: "booking_id IS NOT NULL",
             name: :credit_ledger_entries_by_booking
           )

    # A debit is reversed at most once.
    create unique_index(:credit_ledger_entries, [:tenant_id, :reverses_entry_id],
             where: "reverses_entry_id IS NOT NULL",
             name: :credit_ledger_entries_one_reversal_per_entry
           )

    # Consuming for a booking debits each lot at most once.
    create unique_index(
             :credit_ledger_entries,
             [:tenant_id, :booking_id, :credit_lot_id],
             where: "booking_id IS NOT NULL AND reason = 'debit'",
             name: :credit_ledger_entries_one_debit_per_booking_lot
           )

    create constraint(:credit_ledger_entries, :credit_ledger_entries_delta_nonzero,
             check: "delta <> 0"
           )

    # Append-only table: revoke mutation for the application role. The inverse is
    # supplied for rollback.
    execute(
      "REVOKE UPDATE, DELETE ON credit_ledger_entries FROM scb_app",
      "GRANT UPDATE, DELETE ON credit_ledger_entries TO scb_app"
    )
  end
end
