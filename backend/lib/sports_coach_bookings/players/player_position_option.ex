defmodule SportsCoachBookings.Players.PlayerPositionOption do
  @moduledoc """
  A tenant-configurable list of positions a player may choose from.

  Seeded with the soccer positions `GK, CB, FB, DM, CM, AM, W, ST`.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "player_position_options" do
    field :tenant_id, :binary_id
    field :code, :string
    field :label, :string
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :code, :label, :position, :active])
    |> Ecto.Changeset.validate_required([:tenant_id, :code])
    |> Ecto.Changeset.validate_length(:code, min: 1, max: 20)
    |> Ecto.Changeset.validate_number(:position, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :code])
  end
end
