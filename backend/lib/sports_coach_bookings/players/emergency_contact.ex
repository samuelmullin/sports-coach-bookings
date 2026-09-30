defmodule SportsCoachBookings.Players.EmergencyContact do
  @moduledoc "A priority-ordered emergency contact for a player."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Players.Player

  @type t :: %__MODULE__{}

  schema "emergency_contacts" do
    field :tenant_id, :binary_id
    field :name, :string
    field :relationship, :string
    field :phone, :string
    field :alt_phone, :string
    field :priority, :integer

    belongs_to :player, Player, foreign_key: :player_id

    timestamps()
  end

  @doc false
  def changeset(contact, attrs) do
    contact
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :player_id,
      :name,
      :relationship,
      :phone,
      :alt_phone,
      :priority
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :player_id, :name, :phone, :priority])
    |> Ecto.Changeset.validate_number(:priority, greater_than_or_equal_to: 1)
  end
end
