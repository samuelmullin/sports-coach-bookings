defmodule SportsCoachBookings.Scheduling.Bookings do
  @moduledoc """
  Seam to the Bookings context (wp-14).

  Session rosters and "is this player already booked?" answers live in wp-14.
  Until it lands, the default source returns empty answers. Tests or a later WP
  can point `config :sports_coach_bookings, :scheduling_bookings_source` at a
  module implementing `session_roster/1` and `player_booked_in_session?/2`.
  """

  @default_source __MODULE__.Empty

  @doc "The roster rows for a session (empty until wp-14 lands)."
  @spec session_roster(binary()) :: [map()]
  def session_roster(session_id), do: source().session_roster(session_id)

  @doc "Whether `player_id` already has a booking in `session_id`."
  @spec player_booked_in_session?(binary(), binary()) :: boolean()
  def player_booked_in_session?(player_id, session_id) do
    source().player_booked_in_session?(player_id, session_id)
  end

  defp source do
    Application.get_env(:sports_coach_bookings, :scheduling_bookings_source, @default_source)
  end

  defmodule Empty do
    @moduledoc false
    def session_roster(_session_id), do: []
    def player_booked_in_session?(_player_id, _session_id), do: false
  end
end
