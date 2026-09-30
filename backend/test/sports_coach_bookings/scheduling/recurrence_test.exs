defmodule SportsCoachBookings.Scheduling.RecurrenceTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Scheduling.Recurrence

  @halifax "America/Halifax"

  defp local_hour(utc, timezone) do
    {:ok, local} = DateTime.shift_zone(utc, timezone)
    {local.hour, local.minute}
  end

  test "keeps 17:00 local across the spring-forward transition" do
    {:ok, occurrences} =
      Recurrence.occurrences(%{
        weekdays: [2],
        start_time_local: ~T[17:00:00],
        duration_minutes: 60,
        starts_on: ~D[2026-03-01],
        ends_on: ~D[2026-03-15],
        timezone: @halifax
      })

    starts = Enum.map(occurrences, & &1.starts_at)

    assert [~U[2026-03-03 21:00:00Z], ~U[2026-03-10 20:00:00Z]] = starts
    assert Enum.all?(starts, &(local_hour(&1, @halifax) == {17, 0}))

    # One hour of wall-clock duration on both sides.
    for %{starts_at: _s, ends_at: e} <- occurrences do
      assert local_hour(e, @halifax) == {18, 0}
    end
  end

  test "keeps 17:00 local across the fall-back transition" do
    {:ok, occurrences} =
      Recurrence.occurrences(%{
        weekdays: [2],
        start_time_local: ~T[17:00:00],
        duration_minutes: 60,
        starts_on: ~D[2026-10-25],
        ends_on: ~D[2026-11-08],
        timezone: @halifax
      })

    starts = Enum.map(occurrences, & &1.starts_at)

    assert [~U[2026-10-27 20:00:00Z], ~U[2026-11-03 21:00:00Z]] = starts
    assert Enum.all?(starts, &(local_hour(&1, @halifax) == {17, 0}))
  end

  test "expands a weekday set within the requested range" do
    {:ok, occurrences} =
      Recurrence.occurrences(%{
        weekdays: [1, 3],
        start_time_local: ~T[09:30:00],
        duration_minutes: 45,
        starts_on: ~D[2026-01-05],
        ends_on: ~D[2026-01-11],
        timezone: "America/Toronto"
      })

    assert length(occurrences) == 2

    dates =
      occurrences
      |> Enum.map(&DateTime.to_date(DateTime.shift_zone!(&1.starts_at, "America/Toronto")))
      |> Enum.sort()

    assert dates == [~D[2026-01-05], ~D[2026-01-07]]
  end

  test "rejects a range that would exceed the per-request cap" do
    assert {:error, :too_many_occurrences} =
             Recurrence.occurrences(%{
               weekdays: [1, 2, 3, 4, 5, 6, 7],
               start_time_local: ~T[09:00:00],
               duration_minutes: 60,
               starts_on: ~D[2026-01-01],
               ends_on: ~D[2027-12-31],
               timezone: "America/Toronto"
             })
  end

  test "reports an unknown timezone" do
    assert {:error, _reason} =
             Recurrence.at("Not/AZone", ~D[2026-01-05], ~T[09:00:00], 60)
  end
end
