defmodule SportsCoachBookings.Tenancy.Storage.Fake do
  @moduledoc """
  Deterministic dev/test storage backend.

  Produces a stable key from the tenant id and filename (so tests can predict
  it) and a presigned-style URL. Nothing is actually uploaded or stored. See
  `docs/rfcs/20260928-tenancy-storage-stub.md`.
  """

  @behaviour SportsCoachBookings.Tenancy.Storage

  @presign_ttl_seconds 900
  @public_base "https://cdn.example.test"

  @impl true
  def presign_put(upload, tenant_id) do
    key = build_key(upload, tenant_id)
    expires_at = DateTime.add(DateTime.utc_now(), @presign_ttl_seconds, :second)

    {:ok,
     %{
       key: key,
       upload_url: "https://fake-s3.invalid/#{key}?X-Amz-Expires=#{@presign_ttl_seconds}",
       method: "PUT",
       headers: %{"Content-Type" => upload.content_type},
       expires_at: expires_at
     }}
  end

  @impl true
  def public_url(key) when is_binary(key), do: "#{@public_base}/#{key}"

  @doc "The deterministic key a given upload maps to."
  @spec build_key(SportsCoachBookings.Tenancy.Storage.upload(), binary()) :: binary()
  def build_key(upload, tenant_id) do
    base =
      case upload.filename do
        nil -> "asset"
        filename -> filename |> Path.basename() |> sanitize()
      end

    "#{tenant_id}/#{base}"
  end

  defp sanitize(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9._-]/, "-")
    |> String.slice(0, 120)
    |> case do
      "" -> "asset"
      value -> value
    end
  end
end
