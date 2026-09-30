defmodule SportsCoachBookings.Bookings.SchedulingSource do
  @moduledoc """
  Implements the Scheduling read seam (wp-11) for session rosters and
  "already booked" checks. Pointed at by
  `config :sports_coach_bookings, :scheduling_bookings_source`.
  """

  alias SportsCoachBookings.Bookings

  @doc "The roster rows for a session (see `Bookings.session_roster/1`)."
  @spec session_roster(binary()) :: [map()]
  def session_roster(session_id), do: Bookings.session_roster(session_id)

  @doc "Whether the player already has a booking in the session."
  @spec player_booked_in_session?(binary(), binary()) :: boolean()
  def player_booked_in_session?(player_id, session_id),
    do: Bookings.player_booked_in_session?(player_id, session_id)
end
