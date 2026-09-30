defmodule SportsCoachBookings.Logger.Formatter do
  @moduledoc """
  Structured (one JSON object per line) log formatter for releases.

  Configured in `config/prod.exs` via:

      config :logger, :default_formatter, format: {SportsCoachBookings.Logger.Formatter, :format}

  Emits `time`, `level`, `message`, and a curated allow-list of metadata
  (`request_id`, `tenant_id`, Oban job fields, `mfa`, `pid`, `node`). Secrets,
  request bodies, and medical values are never in Logger metadata, but the
  allow-list keeps the log line small and PII-free regardless.

  This mirrors the JSON shape used by Fly's log drain and by most error
  trackers, so no collector-side parsing is required.
  """

  @meta_allowlist ~w(
    request_id tenant_id mfa pid node oban
    queue job_id worker_id attempt state
    kind reason source error event duration
  )a

  @doc false
  @spec format(Logger.level(), term(), term(), keyword()) :: iodata()
  def format(level, message, timestamp, metadata) do
    entry =
      %{
        "time" => format_timestamp(timestamp),
        "level" => Atom.to_string(level),
        "message" => format_message(message)
      }
      |> put_metadata(metadata)

    [Jason.encode_to_iodata!(entry), ?\n]
  end

  defp put_metadata(entry, metadata) do
    Enum.reduce(@meta_allowlist, entry, fn key, acc ->
      case Access.fetch(metadata, key) do
        {:ok, value} -> Map.put(acc, Atom.to_string(key), safe(value))
        :error -> acc
      end
    end)
  end

  # `Logger.Formatter` passes metadata values as-is; encode anything that Jason
  # cannot handle as a string via inspect/2.
  defp safe(value) do
    Jason.encode!(value)
    value
  rescue
    _ -> inspect(value)
  end

  defp format_message({:string, message}), do: IO.iodata_to_binary(message)
  defp format_message({:report, report}), do: inspect(report)
  defp format_message(message) when is_binary(message), do: message
  defp format_message(message) when is_list(message), do: IO.iodata_to_binary(message)
  defp format_message(message), do: inspect(message)

  defp format_timestamp({{year, month, day}, {hour, minute, second, millisecond}}) do
    format_iso8601(year, month, day, hour, minute, second, millisecond)
  end

  defp format_timestamp({{year, month, day}, {hour, minute, second}}) do
    format_iso8601(year, month, day, hour, minute, second, 0)
  end

  defp format_iso8601(year, month, day, hour, minute, second, millisecond) do
    :io_lib.format(
      "~4..0b-~2..0b-~2..0bT~2..0b:~2..0b:~2..0b.~3..0bZ",
      [year, month, day, hour, minute, second, millisecond]
    )
    |> IO.iodata_to_binary()
  end
end
