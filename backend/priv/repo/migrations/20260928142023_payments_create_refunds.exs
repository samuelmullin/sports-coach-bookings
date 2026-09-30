defmodule SportsCoachBookings.Repo.Migrations.PaymentsCreateRefunds do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Refunds issued against a payment. Tenant-owned (RLS enabled and forced).
    # `payment_id` is a within-context FK. `actor_type`/`actor_id` follow the
    # Core.Audit actor shape (refunds.actor is unspecified in the ERD).
    tenant_table :refunds do
      add :payment_id, references(:payments, type: :uuid, on_delete: :delete_all), null: false
      add :amount, :integer, null: false
      add :reason, :text
      add :refund_ref, :string
      add :status, :string, null: false, default: "pending"
      add :actor_type, :string
      add :actor_id, :uuid
    end

    create index(:refunds, [:payment_id])

    # Replaying a `charge.refunded` webhook must not create a second refund row.
    create unique_index(:refunds, [:tenant_id, :refund_ref])
  end
end
