defmodule SportsCoachBookings.Players.AuthorizedPickup do
  @moduledoc "A person authorised to collect a player, when restrictions apply."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Players.Player

  @type t :: %__MODULE__{}

  schema "authorized_pickups" do
    field :tenant_id, :binary_id
    field :name, :string
    field :relationship, :string
    field :phone, :string
    field :notes, :string

    belongs_to :player, Player, foreign_key: :player_id

    timestamps()
  end

  @doc false
  def changeset(pickup, attrs) do
    pickup
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :player_id,
      :name,
      :relationship,
      :phone,
      :notes
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :player_id, :name])
  end
end
