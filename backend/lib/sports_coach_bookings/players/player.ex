defmodule SportsCoachBookings.Players.Player do
  @moduledoc """
  A person a household books coaching for (a minor or an adult booking for
  themselves). Owned by WP-06.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Players.AuthorizedPickup
  alias SportsCoachBookings.Players.EmergencyContact
  alias SportsCoachBookings.Players.MedicalInfo
  alias SportsCoachBookings.Players.PlayerProfile

  @type t :: %__MODULE__{}

  schema "players" do
    field :tenant_id, :binary_id
    # Cross-context reference to Customers.households; plain uuid, no FK while
    # the households table is unmerged. See the RFC.
    field :household_id, :binary_id
    field :first_name, :string
    field :last_name, :string
    field :preferred_name, :string
    field :date_of_birth, :date
    field :is_self, :boolean, default: false
    field :photo_key, :string
    field :active, :boolean, default: true
    field :no_pickup_restrictions, :boolean, default: false

    has_one :profile, PlayerProfile, foreign_key: :player_id

    has_many :emergency_contacts, EmergencyContact,
      foreign_key: :player_id,
      preload_order: [asc: :priority]

    has_many :authorized_pickups, AuthorizedPickup, foreign_key: :player_id
    has_one :medical_info, MedicalInfo, foreign_key: :player_id

    timestamps()
  end

  @doc false
  def changeset(player, attrs) do
    player
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :household_id,
      :first_name,
      :last_name,
      :preferred_name,
      :date_of_birth,
      :is_self,
      :photo_key,
      :active,
      :no_pickup_restrictions
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :household_id,
      :first_name,
      :last_name,
      :date_of_birth
    ])
    |> Ecto.Changeset.validate_length(:first_name, min: 1, max: 100)
    |> Ecto.Changeset.validate_length(:last_name, min: 1, max: 100)
    |> Ecto.Changeset.validate_length(:preferred_name, max: 100)
    |> reject_future_date_of_birth()
  end

  @doc "The name to show in rosters: the preferred name when present, else first."
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{preferred_name: preferred})
      when is_binary(preferred) and preferred != "",
      do: preferred

  def display_name(%__MODULE__{first_name: first}), do: first

  defp reject_future_date_of_birth(changeset) do
    Ecto.Changeset.validate_change(changeset, :date_of_birth, fn :date_of_birth, dob ->
      if Date.compare(dob, Date.utc_today()) == :gt,
        do: [date_of_birth: "must not be in the future"],
        else: []
    end)
  end
end
