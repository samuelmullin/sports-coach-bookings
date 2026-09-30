defmodule SportsCoachBookings.Notifications.Ics do
  @moduledoc """
  Minimal RFC 5545 iCalendar generation for booking emails.

  Only the subset needed by transactional booking mail is produced: a single
  `VEVENT` inside a `VCALENDAR`, with a stable `UID` per booking so a reschedule
  is an update (same `UID`, bumped `SEQUENCE`) rather than a new event. Times
  are emitted with the venue's `TZID` so they render in the venue's local zone.
  """

  @prodid "-//SportsCoachBookings//Bookings//EN"
  @uid_domain "sportscoachbookings.com"
  @fold_width 73

  @doc """
  Builds a one-event calendar for a booking.

  Accepts a map with `:uid`, `:sequence`, `:starts_at`, `:ends_at`,
  `:timezone`, `:summary`, `:location`, and optional `:description`, `:now`.
  """
  @spec for_booking(map()) :: String.t()
  def for_booking(args) when is_map(args) do
    uid = "#{Map.fetch!(args, :uid)}@#{@uid_domain}"
    sequence = Map.get(args, :sequence, 0) || 0
    timezone = Map.get(args, :timezone) || "Etc/UTC"
    stamp = format_utc(Map.get(args, :now) || DateTime.utc_now())

    lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:#{@prodid}",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:#{uid}",
      "SEQUENCE:#{sequence}",
      "DTSTAMP:#{stamp}",
      datetime_line("DTSTART", Map.fetch!(args, :starts_at), timezone),
      datetime_line("DTEND", Map.fetch!(args, :ends_at), timezone),
      "SUMMARY:#{escape(Map.fetch!(args, :summary))}",
      "LOCATION:#{escape(Map.get(args, :location) || "")}",
      "DESCRIPTION:#{escape(Map.get(args, :description) || "")}",
      "END:VEVENT",
      "END:VCALENDAR"
    ]

    lines
    |> Enum.flat_map(&fold/1)
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  defp datetime_line(name, %DateTime{} = datetime, timezone) do
    {zoned, _} = shift(datetime, timezone)
    "#{name};TZID=#{timezone}:#{format_local(zoned)}"
  end

  defp shift(datetime, timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted} -> {shifted, timezone}
      {:error, _} -> {DateTime.shift_zone!(datetime, "Etc/UTC"), "Etc/UTC"}
    end
  end

  defp format_local(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601(:basic)
    |> String.replace("Z", "")
  end

  defp format_utc(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601(:basic)
    |> Kernel.<>("Z")
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\r\n", "\\n")
    |> String.replace("\n", "\\n")
  end

  defp fold(line) when is_binary(line), do: do_fold(line, [], true)

  defp do_fold("", acc, _first), do: Enum.reverse(acc)

  defp do_fold(line, acc, first) do
    {head, rest} = String.split_at(line, @fold_width)
    chunk = if first, do: head, else: " " <> head
    do_fold(rest, [chunk | acc], false)
  end
end
