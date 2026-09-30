defmodule SportsCoachBookings.Players.PlayerProfile do
  @moduledoc "Sporting profile for a player. One row per player."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Players.Player

  @type t :: %__MODULE__{}

  schema "player_profiles" do
    field :tenant_id, :binary_id
    field :home_club, :string
    field :team, :string
    field :preferred_positions, {:array, :string}, default: []
    field :dominant_foot, :string
    field :goals, :string
    field :interests, {:array, :string}, default: []
    field :notes_from_family, :string

    belongs_to :player, Player, foreign_key: :player_id

    timestamps()
  end

  @doc false
  def changeset(profile, attrs) do
    profile
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :player_id,
      :home_club,
      :team,
      :preferred_positions,
      :dominant_foot,
      :goals,
      :interests,
      :notes_from_family
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :player_id])
    |> Ecto.Changeset.validate_length(:home_club, max: 200)
    |> Ecto.Changeset.validate_length(:team, max: 200)
    |> Ecto.Changeset.validate_length(:dominant_foot, max: 50)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :player_id])
  end
end
