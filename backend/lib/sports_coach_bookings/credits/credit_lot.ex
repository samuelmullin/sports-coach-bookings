defmodule SportsCoachBookings.Credits.CreditLot do
  @moduledoc """
  A lot of credits granted to a household. Owned by WP-12.

  `remaining` is a cached value; the invariant is
  `remaining == sum(credit_ledger_entries.delta)` for the lot. Every change to
  `remaining` is accompanied by a matching ledger entry in the same transaction
  (see `SportsCoachBookings.Credits`).
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Credits.CreditLedgerEntry

  @type t :: %__MODULE__{}

  @sources [:package_purchase, :admin_grant, :return_grace]

  schema "credit_lots" do
    field :tenant_id, :binary_id
    field :household_id, :binary_id
    field :source, Ecto.Enum, values: @sources
    field :order_line_id, :binary_id
    field :package_id, :binary_id
    field :eligible_offering_ids, {:array, :binary_id}, default: []
    field :quantity_granted, :integer
    field :remaining, :integer
    field :expires_at, :utc_datetime_usec
    field :granted_at, :utc_datetime_usec
    field :expiring_soon_notified_at, :utc_datetime_usec

    has_many :ledger_entries, CreditLedgerEntry, foreign_key: :credit_lot_id

    timestamps()
  end

  @doc false
  def changeset(lot, attrs) do
    lot
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :household_id,
      :source,
      :order_line_id,
      :package_id,
      :eligible_offering_ids,
      :quantity_granted,
      :remaining,
      :expires_at,
      :granted_at,
      :expiring_soon_notified_at
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :household_id,
      :source,
      :quantity_granted,
      :remaining,
      :granted_at
    ])
    |> Ecto.Changeset.validate_number(:quantity_granted, greater_than: 0)
    |> Ecto.Changeset.validate_number(:remaining, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.check_constraint(:quantity_granted, name: :credit_lots_quantity_positive)
    |> Ecto.Changeset.check_constraint(:remaining, name: :credit_lots_remaining_bounds)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :order_line_id],
      name: :credit_lots_one_per_order_line
    )
  end

  @doc "The lot sources."
  @spec sources() :: [atom()]
  def sources, do: @sources

  @doc "Whether the lot has expired at `now`."
  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}, _now), do: false

  def expired?(%__MODULE__{expires_at: expires_at}, now),
    do: DateTime.compare(expires_at, now) != :gt

  @doc """
  Whether the lot may be spent on `offering_id` at `now`.

  An empty `eligible_offering_ids` means the lot is valid for any offering.
  """
  @spec eligible_for?(t(), binary(), DateTime.t()) :: boolean()
  def eligible_for?(%__MODULE__{} = lot, offering_id, now \\ DateTime.utc_now()) do
    lot.remaining > 0 and not expired?(lot, now) and
      (lot.eligible_offering_ids == [] or offering_id in lot.eligible_offering_ids)
  end
end
