defmodule SportsCoachBookings.Waivers.PdfStore.S3 do
  @moduledoc """
  S3-compatible `SportsCoachBookings.Waivers.PdfStore` (AWS S3, R2, RustFS, MinIO).

  Reuses the SigV4 presigner from `SportsCoachBookings.Tenancy.Storage.S3` and
  the same credentials/endpoint config; the app performs the request itself, so
  nothing is exposed to browsers. Set `:private_bucket` (env `S3_PRIVATE_BUCKET`)
  to keep waivers out of the public assets bucket; otherwise the shared bucket
  is used and its policy must not allow public reads of the `<tenant_id>/waivers/`
  prefixes. `:req_options` (tests only) are merged into every `Req` request.

  Request construction is covered with `Req.Test`, and CI performs a live
  put/get/delete round trip against RustFS. Validate the production provider in
  staging as well.
  """

  @behaviour SportsCoachBookings.Waivers.PdfStore

  alias SportsCoachBookings.Tenancy.Storage.S3, as: Signer

  @ttl 60

  @impl true
  def put(key, pdf) do
    case request(:put, key, body: pdf, headers: [{"content-type", "application/pdf"}]) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      other -> failure(other)
    end
  end

  @impl true
  def get(key) do
    case request(:get, key, []) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> failure(other)
    end
  end

  @impl true
  def delete(key) do
    case request(:delete, key, []) do
      {:ok, %{status: status}} when status in 200..299 or status == 404 -> :ok
      other -> failure(other)
    end
  end

  defp request(method, key, opts) do
    config = config()
    url = Signer.presigned_url(method, key, config, @ttl, DateTime.utc_now())

    [method: method, url: url, retry: false, decode_body: false]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Keyword.merge(opts)
    |> Req.request()
  end

  defp config do
    base = Application.get_env(:sports_coach_bookings, Signer, [])

    case Keyword.get(base, :private_bucket) do
      nil -> base
      bucket -> Keyword.put(base, :bucket, bucket)
    end
  end

  defp failure({:ok, %{status: status}}), do: {:error, {:http_status, status}}
  defp failure({:error, reason}), do: {:error, reason}
end
