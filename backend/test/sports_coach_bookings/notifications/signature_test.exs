defmodule SportsCoachBookings.Notifications.SignatureTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Notifications.Signature

  @raw_secret "known-test-secret"
  @secret "whsec_" <> Base.encode64(@raw_secret)

  defp headers(payload, opts \\ []) do
    id = Keyword.get(opts, :id, "msg_1")
    timestamp = Keyword.get(opts, :timestamp, Integer.to_string(System.system_time(:second)))
    signature = Keyword.get(opts, :signature, compute(payload, id, timestamp))

    %{
      "svix-id" => id,
      "svix-timestamp" => timestamp,
      "svix-signature" => signature
    }
  end

  defp compute(payload, id, timestamp) do
    mac = :crypto.mac(:hmac, :sha256, @raw_secret, "#{id}.#{timestamp}.#{payload}")
    "v1," <> Base.encode64(mac)
  end

  test "accepts a valid signature" do
    payload = ~s({"type":"email.delivered"})
    assert :ok = Signature.verify(payload, headers(payload), @secret)
  end

  test "accepts a signature among several" do
    payload = ~s({"type":"email.delivered"})

    headers = %{
      headers(payload)
      | "svix-signature" => "v1,AAAA " <> compute(payload, "msg_1", current_ts())
    }

    assert :ok = Signature.verify(payload, headers, @secret)
  end

  test "rejects a tampered payload" do
    payload = ~s({"type":"email.delivered"})
    headers = headers(payload)

    assert {:error, :invalid_signature} =
             Signature.verify(~s({"type":"email.bounced"}), headers, @secret)
  end

  test "requires the secret" do
    payload = ~s({"type":"email.delivered"})
    assert {:error, :missing_secret} = Signature.verify(payload, headers(payload), nil)
  end

  test "enforces the timestamp tolerance when asked" do
    payload = ~s({"type":"email.delivered"})
    old = Integer.to_string(System.system_time(:second) - 10_000)
    headers = headers(payload, timestamp: old)

    assert :ok = Signature.verify(payload, headers, @secret)

    assert {:error, :invalid_timestamp} =
             Signature.verify(payload, headers, @secret, tolerance: 300)
  end

  defp current_ts, do: Integer.to_string(System.system_time(:second))
end
