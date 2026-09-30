defmodule SportsCoachBookings.Inventory.StockMovement do
  @moduledoc """
  Append-only stock ledger. Owned by WP-08.

  `on_hand` equals the sum of the non-reservation movements
  (`received | sold | adjusted | returned`); `reserved` equals the sum of the
  reservation movements (`reserved | released`). Rows are never updated or
  deleted: the `scb_app` role has `UPDATE`/`DELETE` revoked.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Inventory.ProductVariant

  @type t :: %__MODULE__{}

  @kinds [:received, :sold, :adjusted, :returned, :reserved, :released]
  @reservation_kinds [:reserved, :released]
  @non_reservation_kinds [:received, :sold, :adjusted, :returned]

  schema "stock_movements" do
    field :tenant_id, :binary_id
    field :delta, :integer
    field :kind, Ecto.Enum, values: @kinds
    field :order_id, :binary_id
    field :actor_type, :string
    field :actor_id, :binary_id
    field :note, :string

    belongs_to :variant, ProductVariant, foreign_key: :variant_id, type: :binary_id

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(movement, attrs) do
    movement
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :variant_id,
      :delta,
      :kind,
      :order_id,
      :actor_type,
      :actor_id,
      :note
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :variant_id, :delta, :kind])
  end

  @doc "All movement kinds."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc "The kinds that move `on_hand` (i.e. non-reservation movements)."
  @spec non_reservation_kinds() :: [atom()]
  def non_reservation_kinds, do: @non_reservation_kinds

  @doc "The kinds that move `reserved` (reservation movements)."
  @spec reservation_kinds() :: [atom()]
  def reservation_kinds, do: @reservation_kinds
end
