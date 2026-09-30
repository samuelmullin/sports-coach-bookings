defmodule SportsCoachBookings.Notifications.Signature do
  @moduledoc """
  Verifies Svix webhook signatures (the scheme Resend uses).

  The signed content is `"<svix-id>.<svix-timestamp>.<body>"`, HMAC-SHA256 with
  the base64-decoded secret (after the `whsec_` prefix), compared against each
  `v1,<base64>` value in the `svix-signature` header using a constant-time
  comparison. The secret is configurable (`:resend_webhook_secret`).
  """

  @doc """
  Verifies a Svix signature.

  `headers` is a map of header names (any case) to values; `secret` is the raw
  `whsec_…` value. Options: `:tolerance` seconds (the default is no timestamp
  check).
  """
  @spec verify(binary(), map(), binary() | nil, keyword()) ::
          :ok | {:error, :missing_secret | :invalid_signature | :invalid_timestamp}
  def verify(payload, headers, secret, opts \\ [])

  def verify(payload, headers, secret, opts) when is_binary(payload) do
    with {:ok, id} <- header(headers, "svix-id"),
         {:ok, timestamp} <- header(headers, "svix-timestamp"),
         {:ok, signature} <- header(headers, "svix-signature"),
         :ok <- check_tolerance(timestamp, opts),
         {:ok, key} <- decode_secret(secret) do
      signed = id <> "." <> timestamp <> "." <> payload
      expected = :crypto.mac(:hmac, :sha256, key, signed)

      if any_signature_matches?(signature, expected) do
        :ok
      else
        {:error, :invalid_signature}
      end
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, :invalid_signature}
    end
  end

  def verify(_payload, _headers, _secret, _opts), do: {:error, :invalid_signature}

  defp any_signature_matches?(header, expected) do
    header
    |> String.split(" ", trim: true)
    |> Enum.any?(fn part ->
      case String.split(part, ",", parts: 2) do
        ["v1", encoded] -> matches?(encoded, expected)
        _ -> false
      end
    end)
  end

  defp matches?(encoded, expected) do
    case Base.decode64(encoded) do
      {:ok, decoded} -> Plug.Crypto.secure_compare(expected, decoded)
      :error -> false
    end
  end

  defp decode_secret(nil), do: {:error, :missing_secret}
  defp decode_secret(""), do: {:error, :missing_secret}

  defp decode_secret("whsec_" <> rest), do: Base.decode64(rest)
  defp decode_secret(secret), do: Base.decode64(secret)

  defp header(headers, name) do
    case Enum.find(headers, fn {key, _} -> String.downcase(to_string(key)) == name end) do
      {_key, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> :error
    end
  end

  defp check_tolerance(timestamp, opts) do
    case Keyword.get(opts, :tolerance) do
      nil -> :ok
      tolerance when is_integer(tolerance) -> check_timestamp(timestamp, tolerance)
    end
  end

  defp check_timestamp(timestamp, tolerance) do
    with {unix, ""} <- Integer.parse(timestamp),
         true <- System.system_time(:second) - unix <= tolerance do
      :ok
    else
      _ -> {:error, :invalid_timestamp}
    end
  end
end
