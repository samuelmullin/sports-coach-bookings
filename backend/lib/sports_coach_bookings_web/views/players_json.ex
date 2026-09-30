defmodule SportsCoachBookingsWeb.PlayersJSON do
  @moduledoc """
  Serialises players and their sub-resources for the staff and portal APIs.

  Medical values are never included here except by `medical_info/1`, which is
  used only by the dedicated medical endpoint.
  """

  alias SportsCoachBookings.Players.AuthorizedPickup
  alias SportsCoachBookings.Players.EmergencyContact
  alias SportsCoachBookings.Players.MedicalInfo
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Players.PlayerPositionOption
  alias SportsCoachBookings.Players.PlayerProfile

  @doc "Serialises a player without medical values or sub-resource detail."
  @spec player(Player.t()) :: map()
  def player(player) do
    %{
      id: player.id,
      household_id: player.household_id,
      first_name: player.first_name,
      last_name: player.last_name,
      preferred_name: player.preferred_name,
      date_of_birth: date(player.date_of_birth),
      age: age(player),
      is_self: player.is_self,
      photo_key: player.photo_key,
      active: player.active,
      no_pickup_restrictions: player.no_pickup_restrictions,
      inserted_at: datetime(player.inserted_at),
      updated_at: datetime(player.updated_at)
    }
  end

  @doc "Serialises a player with profile, contacts, and pickups (never medical)."
  @spec player_detail(Player.t()) :: map()
  def player_detail(player) do
    player
    |> player()
    |> Map.put(:profile, player.profile && profile(player.profile))
    |> Map.put(
      :emergency_contacts,
      Enum.map(player.emergency_contacts || [], &emergency_contact/1)
    )
    |> Map.put(
      :authorized_pickups,
      Enum.map(player.authorized_pickups || [], &authorized_pickup/1)
    )
    |> Map.put(:has_medical_info, !!(player.medical_info && player.medical_info.has_medical_info))
  end

  @doc "Serialises a player's profile."
  @spec profile(PlayerProfile.t()) :: map()
  def profile(profile) do
    %{
      id: profile.id,
      player_id: profile.player_id,
      home_club: profile.home_club,
      team: profile.team,
      preferred_positions: profile.preferred_positions,
      dominant_foot: profile.dominant_foot,
      goals: profile.goals,
      interests: profile.interests,
      notes_from_family: profile.notes_from_family,
      inserted_at: datetime(profile.inserted_at),
      updated_at: datetime(profile.updated_at)
    }
  end

  @doc "Serialises an emergency contact."
  @spec emergency_contact(EmergencyContact.t()) :: map()
  def emergency_contact(contact) do
    %{
      id: contact.id,
      player_id: contact.player_id,
      name: contact.name,
      relationship: contact.relationship,
      phone: contact.phone,
      alt_phone: contact.alt_phone,
      priority: contact.priority
    }
  end

  @doc "Serialises an authorized pickup."
  @spec authorized_pickup(AuthorizedPickup.t()) :: map()
  def authorized_pickup(pickup) do
    %{
      id: pickup.id,
      player_id: pickup.player_id,
      name: pickup.name,
      relationship: pickup.relationship,
      phone: pickup.phone,
      notes: pickup.notes
    }
  end

  @doc "Serialises decrypted medical info. Only the medical endpoint may use this."
  @spec medical_info(MedicalInfo.t()) :: map()
  def medical_info(medical) do
    %{
      id: medical.id,
      player_id: medical.player_id,
      allergies: medical.allergies,
      conditions: medical.conditions,
      medications: medical.medications,
      notes: medical.notes,
      has_medical_info: medical.has_medical_info,
      updated_at: datetime(medical.updated_at)
    }
  end

  @doc "Serialises a position option."
  @spec position_option(PlayerPositionOption.t()) :: map()
  def position_option(option) do
    %{
      id: option.id,
      code: option.code,
      label: option.label,
      position: option.position,
      active: option.active
    }
  end

  @doc "Serialises a roster summary (name, age, positions, medical flag, contact)."
  @spec summary(map()) :: map()
  def summary(summary), do: summary

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp age(%Player{date_of_birth: %Date{} = _dob} = player) do
    SportsCoachBookings.Players.age_on(player, Date.utc_today())
  end

  defp date(nil), do: nil
  defp date(value), do: Date.to_iso8601(value)

  defp datetime(nil), do: nil
  defp datetime(value), do: DateTime.to_iso8601(value)
end
