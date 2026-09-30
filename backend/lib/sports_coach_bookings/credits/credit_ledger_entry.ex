defmodule SportsCoachBookings.Credits.CreditLedgerEntry do
  @moduledoc """
  An append-only credit ledger entry. Owned by WP-12.

  Rows are never updated or deleted: the `scb_app` role has `UPDATE`/`DELETE`
  revoked. Corrections are made by appending a reversing entry
  (`reverses_entry_id` points at the entry being reversed).
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Credits.CreditLot

  @type t :: %__MODULE__{}

  @reasons [:grant, :debit, :reversal, :expire, :adjust]

  schema "credit_ledger_entries" do
    field :tenant_id, :binary_id
    field :household_id, :binary_id
    field :delta, :integer
    field :reason, Ecto.Enum, values: @reasons
    field :booking_id, :binary_id
    field :reverses_entry_id, :binary_id
    field :actor_type, :string
    field :actor_id, :binary_id
    field :note, :string

    belongs_to :credit_lot, CreditLot, foreign_key: :credit_lot_id, type: :binary_id

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :credit_lot_id,
      :household_id,
      :delta,
      :reason,
      :booking_id,
      :reverses_entry_id,
      :actor_type,
      :actor_id,
      :note
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :credit_lot_id,
      :household_id,
      :delta,
      :reason
    ])
    |> Ecto.Changeset.check_constraint(:delta, name: :credit_ledger_entries_delta_nonzero)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :reverses_entry_id],
      name: :credit_ledger_entries_one_reversal_per_entry
    )
    |> Ecto.Changeset.unique_constraint([:tenant_id, :booking_id, :credit_lot_id],
      name: :credit_ledger_entries_one_debit_per_booking_lot
    )
  end

  @doc "The ledger reasons."
  @spec reasons() :: [atom()]
  def reasons, do: @reasons
end
