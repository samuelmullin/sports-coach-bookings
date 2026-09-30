defmodule SportsCoachBookingsWeb.SchedulingJSON do
  @moduledoc "Serialises scheduling sessions, calendar entries, and series."

  alias SportsCoachBookings.Catalog.Offering
  alias SportsCoachBookings.Catalog.Venue
  alias SportsCoachBookings.Scheduling.Session
  alias SportsCoachBookings.Scheduling.SessionSeries
  alias SportsCoachBookings.Staff.Membership

  @doc "Serialises a session."
  @spec session(Session.t()) :: map()
  def session(%Session{} = session) do
    %{
      id: session.id,
      offering_id: session.offering_id,
      venue_id: session.venue_id,
      starts_at: datetime(session.starts_at),
      ends_at: datetime(session.ends_at),
      capacity: session.capacity,
      booked_count: session.booked_count,
      held_count: session.held_count,
      seats_left: Session.seats_left(session),
      status: to_string(session.status),
      visibility: to_string(session.visibility),
      title_override: session.title_override,
      notes_public: session.notes_public,
      notes_staff: session.notes_staff,
      show_coaches: session.show_coaches,
      series_id: session.series_id,
      cancel_reason: session.cancel_reason,
      inserted_at: datetime(session.inserted_at),
      updated_at: datetime(session.updated_at)
    }
  end

  @doc "Serialises a calendar entry (session + related summaries + availability)."
  @spec calendar_entry(map()) :: map()
  def calendar_entry(entry) do
    %{
      session: session(entry.session),
      offering: offering(entry.offering),
      venue: venue(entry.venue),
      coaches: Enum.map(entry.coaches, &coach/1),
      seats_left: entry.seats_left,
      bookable: entry.bookable,
      not_bookable_reason: stringify(entry.not_bookable_reason),
      already_booked: Map.get(entry, :already_booked, false),
      warnings: Enum.map(entry.warnings, &warning/1)
    }
    |> maybe_put_roster(Map.get(entry, :roster))
  end

  @doc "Serialises a session series."
  @spec series(SessionSeries.t()) :: map()
  def series(%SessionSeries{} = series) do
    %{
      id: series.id,
      weekdays: series.weekdays,
      start_time_local: time(series.start_time_local),
      duration_minutes: series.duration_minutes,
      starts_on: date(series.starts_on),
      ends_on: date(series.ends_on),
      timezone: series.timezone,
      offering_id: series.offering_id,
      venue_id: series.venue_id,
      inserted_at: datetime(series.inserted_at),
      updated_at: datetime(series.updated_at)
    }
  end

  @doc "Serialises a conflict warning."
  @spec warning(map()) :: map()
  def warning(warning) do
    %{
      type: stringify(warning.type),
      session_id: warning.session_id,
      conflicting_session_id: warning.conflicting_session_id,
      membership_id: Map.get(warning, :membership_id),
      starts_at: datetime(Map.get(warning, :starts_at))
    }
  end

  @doc "Serialises a cancel result (`%{session:, impact:}`)."
  @spec cancelled(map()) :: map()
  def cancelled(%{session: session, impact: impact}) do
    %{session: session(session), impact: impact}
  end

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp offering(nil), do: nil

  defp offering(%Offering{} = offering) do
    %{
      id: offering.id,
      name: offering.name,
      slug: offering.slug,
      description: offering.description,
      format: to_string(offering.format),
      duration_minutes: offering.duration_minutes,
      min_age: offering.min_age,
      max_age: offering.max_age,
      default_capacity: offering.default_capacity,
      credit_cost: offering.credit_cost,
      drop_in_price: offering.drop_in_price,
      bookable_until_minutes_before: offering.bookable_until_minutes_before,
      bookable_from_days_ahead: offering.bookable_from_days_ahead
    }
  end

  defp venue(nil), do: nil

  defp venue(%Venue{} = venue) do
    %{id: venue.id, name: venue.name, timezone: venue.timezone}
  end

  defp coach(%Membership{} = membership) do
    %{
      membership_id: membership.id,
      display_name: membership.display_name,
      role: to_string(membership.role)
    }
  end

  defp maybe_put_roster(map, nil), do: map
  defp maybe_put_roster(map, roster), do: Map.put(map, :roster, roster)

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp date(nil), do: nil
  defp date(%Date{} = value), do: Date.to_iso8601(value)

  defp time(nil), do: nil
  defp time(%Time{} = value), do: Time.to_iso8601(value)
end
