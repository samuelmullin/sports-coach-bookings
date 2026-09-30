defmodule SportsCoachBookings.Scheduling.Recurrence do
  @moduledoc """
  DST-safe expansion of a recurrence definition into concrete UTC instants.

  Occurrences are generated from the **local** date plus the local wall-clock
  start time in the series timezone, then converted to UTC. That keeps e.g.
  "Tuesdays 17:00 America/Halifax" at 17:00 local on both sides of a
  daylight-saving change (the UTC instant shifts by an hour).

  This module is pure: it reads no clock and touches no database. It is used at
  session/series creation and edit time only — sessions are always materialised.
  """

  alias SportsCoachBookings.Scheduling.SessionSeries

  @max_occurrences 200
  @default_weeks 12

  @type occurrence :: %{starts_at: DateTime.t(), ends_at: DateTime.t()}

  @doc "The maximum number of occurrences a single request may materialise."
  @spec max_occurrences() :: pos_integer()
  def max_occurrences, do: @max_occurrences

  @doc """
  Expands a series definition into UTC occurrences.

  Accepts the columns of `SessionSeries` (as a struct or a normalised map).
  Returns `{:error, :too_many_occurrences}` when the range would produce more
  than `max_occurrences/0` rows, and `{:error, :invalid_timezone}` for an
  unknown IANA timezone.
  """
  @spec occurrences(SessionSeries.t() | map()) ::
          {:ok, [occurrence()]} | {:error, atom()}
  def occurrences(%SessionSeries{} = series) do
    occurrences(%{
      weekdays: series.weekdays,
      start_time_local: series.start_time_local,
      duration_minutes: series.duration_minutes,
      starts_on: series.starts_on,
      ends_on: series.ends_on,
      timezone: series.timezone
    })
  end

  def occurrences(attrs) do
    weekdays = Map.fetch!(attrs, :weekdays)
    start_time = Map.fetch!(attrs, :start_time_local)
    duration = Map.fetch!(attrs, :duration_minutes)
    starts_on = Map.fetch!(attrs, :starts_on)
    timezone = Map.fetch!(attrs, :timezone)
    ends_on = Map.get(attrs, :ends_on) || Date.add(starts_on, 7 * @default_weeks)

    dates =
      starts_on
      |> Date.range(ends_on)
      |> Enum.filter(&(Date.day_of_week(&1) in weekdays))

    if length(dates) > @max_occurrences do
      {:error, :too_many_occurrences}
    else
      build_occurrences(dates, start_time, duration, timezone)
    end
  end

  @doc """
  Builds a single occurrence for `local_date` in `timezone`.

  Used by series edits that change the wall-clock start time.
  """
  @spec at(String.t(), Date.t(), Time.t(), non_neg_integer()) ::
          {:ok, occurrence()} | {:error, atom()}
  def at(timezone, local_date, start_time, duration_minutes) do
    case DateTime.new(local_date, start_time, timezone) do
      {:ok, starts_at} ->
        {:ok, span(DateTime.shift_zone!(starts_at, "Etc/UTC"), duration_minutes)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The local date of a UTC instant in `timezone`."
  @spec local_date(DateTime.t(), String.t()) :: Date.t()
  def local_date(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> DateTime.to_date(local)
      {:error, _} -> DateTime.to_date(utc)
    end
  end

  defp span(starts_at, duration_minutes) do
    %{starts_at: starts_at, ends_at: DateTime.add(starts_at, duration_minutes * 60, :second)}
  end

  defp build_occurrences(dates, start_time, duration, timezone) do
    Enum.reduce_while(dates, {:ok, []}, fn date, {:ok, acc} ->
      case at(timezone, date, start_time, duration) do
        {:ok, occurrence} -> {:cont, {:ok, [occurrence | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, occurrences} -> {:ok, Enum.reverse(occurrences)}
      other -> other
    end
  end
end
