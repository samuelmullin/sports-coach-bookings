defmodule SportsCoachBookings.Notifications.IcsTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Notifications.Ics

  @base %{
    uid: "booking-1",
    sequence: 0,
    starts_at: ~U[2026-01-06 22:00:00.000000Z],
    ends_at: ~U[2026-01-06 23:00:00.000000Z],
    timezone: "America/Toronto",
    summary: "U12 Skills",
    location: "Riverside Field",
    description: "Cancellation policy applies"
  }

  test "produces a well-formed single-event VCALENDAR" do
    properties = @base |> Ics.for_booking() |> parse()

    assert List.first(properties) == "BEGIN:VCALENDAR"
    assert List.last(properties) == "END:VCALENDAR"
    assert "VERSION:2.0" in properties
    assert "BEGIN:VEVENT" in properties
    assert "END:VEVENT" in properties
    assert "UID:booking-1@sportscoachbookings.com" in properties
    assert "SUMMARY:U12 Skills" in properties
    assert "LOCATION:Riverside Field" in properties
  end

  test "renders DTSTART/DTEND in the venue timezone" do
    properties = @base |> Ics.for_booking() |> parse()

    assert "DTSTART;TZID=America/Toronto:20260106T170000" in properties
    assert "DTEND;TZID=America/Toronto:20260106T180000" in properties
    assert "DTSTAMP:" <> _ = Enum.find(properties, &String.starts_with?(&1, "DTSTAMP:"))
  end

  test "a reschedule keeps the UID and bumps SEQUENCE" do
    first = @base |> Ics.for_booking() |> parse()
    moved = @base |> Map.put(:sequence, 1) |> Ics.for_booking() |> parse()

    assert "UID:booking-1@sportscoachbookings.com" in first
    assert "UID:booking-1@sportscoachbookings.com" in moved
    assert "SEQUENCE:0" in first
    assert "SEQUENCE:1" in moved
  end

  test "escapes and unfolds long lines" do
    long = String.duplicate("a", 200)
    properties = %{@base | description: long} |> Ics.for_booking() |> parse()

    assert "DESCRIPTION:" <> description =
             Enum.find(properties, &String.starts_with?(&1, "DESCRIPTION:"))

    assert description == long
  end

  test "escapes reserved characters" do
    properties = %{@base | description: "a, b; c\\nd"} |> Ics.for_booking() |> parse()
    assert "DESCRIPTION:a\\, b\\; c\\\\nd" in properties
  end

  # A minimal RFC 5545 reader: normalises CRLF line endings and unfolds
  # continuation lines (leading space) before returning the property lines.
  defp parse(ics) do
    ics
    |> String.replace("\r\n", "\n")
    |> String.split("\n", trim: true)
    |> Enum.reduce([], fn
      <<" ", rest::binary>>, [previous | tail] -> [previous <> rest | tail]
      line, acc -> [line | acc]
    end)
    |> Enum.reverse()
  end
end
