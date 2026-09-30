defmodule SportsCoachBookings.Tenancy.Storage.S3 do
  @moduledoc """
  S3-compatible object storage backend (AWS S3, Cloudflare R2, MinIO, ...).

  Implements `SportsCoachBookings.Tenancy.Storage` using **AWS Signature V4
  presigned PUT URLs**, so no credentials or bytes ever pass through the app.
  It is selected at runtime only when an S3 bucket is configured (see
  `config/runtime.exs`); dev/test keep the deterministic
  `SportsCoachBookings.Tenancy.Storage.Fake`.

  Configuration (all under this module, read at call time):

      config :sports_coach_bookings, SportsCoachBookings.Tenancy.Storage.S3,
        bucket: "scb-uploads",
        region: "ca-central-1",
        access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
        secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY"),
        endpoint: nil,                 # set for MinIO/R2; nil = AWS
        public_base_url: nil,          # CDN/base URL for reads; defaults to the bucket URL
        presign_ttl_seconds: 900,
        force_path_style: false

  > **Not verified against a live bucket in this repo.** There are no S3
  > credentials in CI/dev, so only the URL-shape/signing tests run. The human
  > deployer must validate an upload round-trip in staging (see `docs/ops.md`).
  """

  @behaviour SportsCoachBookings.Tenancy.Storage

  @algorithm "AWS4-HMAC-SHA256"
  @service "s3"
  @unsigned_payload "UNSIGNED-PAYLOAD"

  @impl true
  def presign_put(upload, tenant_id) do
    config = config()
    key = build_key(upload, tenant_id)
    ttl = Keyword.get(config, :presign_ttl_seconds, 900)
    now = Keyword.get(config, :now) || DateTime.utc_now()
    expires_at = DateTime.add(now, ttl, :second)

    url = presigned_url(:put, key, config, ttl, now)

    {:ok,
     %{
       key: key,
       upload_url: url,
       method: "PUT",
       headers: %{"Content-Type" => upload.content_type},
       expires_at: expires_at
     }}
  end

  @impl true
  def public_url(key) when is_binary(key) do
    config = config()

    case Keyword.get(config, :public_base_url) do
      nil -> "#{base_url(config)}/#{key}"
      base -> "#{String.trim_trailing(base, "/")}/#{key}"
    end
  end

  @doc "The object key for an upload (tenant-partitioned, sanitised)."
  @spec build_key(SportsCoachBookings.Tenancy.Storage.upload(), binary()) :: binary()
  def build_key(upload, tenant_id) do
    base =
      case upload.filename do
        nil -> "asset"
        filename -> filename |> Path.basename() |> sanitize()
      end

    "#{tenant_id}/#{base}"
  end

  @doc """
  Builds a presigned URL. Exposed for tests; `now` and `config` are injectable.
  """
  @spec presigned_url(atom(), binary(), keyword(), pos_integer(), DateTime.t()) :: binary()
  def presigned_url(method, key, config, expires, %DateTime{} = now) do
    {scheme, host, path} = host_and_path(config, key)
    region = fetch!(config, :region)
    access_key = fetch!(config, :access_key_id)
    secret = fetch!(config, :secret_access_key)

    amz_date = amz_date(now)
    date = binary_part(amz_date, 0, 8)
    scope = "#{date}/#{region}/#{@service}/aws4_request"

    query =
      [
        {"X-Amz-Algorithm", @algorithm},
        {"X-Amz-Credential", "#{access_key}/#{scope}"},
        {"X-Amz-Date", amz_date},
        {"X-Amz-Expires", Integer.to_string(expires)},
        {"X-Amz-SignedHeaders", "host"}
      ]
      |> canonical_query()

    canonical_request =
      [
        method |> Atom.to_string() |> String.upcase(),
        path,
        query,
        "host:#{host}\n",
        "host",
        @unsigned_payload
      ]
      |> Enum.join("\n")

    string_to_sign =
      [
        @algorithm,
        amz_date,
        scope,
        sha256_hex(canonical_request)
      ]
      |> Enum.join("\n")

    signature =
      Base.encode16(signing_key(secret, date, region, @service) |> hmac(string_to_sign),
        case: :lower
      )

    "#{scheme}://#{host}#{path}?#{query}&X-Amz-Signature=#{signature}"
  end

  # --- config ---------------------------------------------------------------

  defp config do
    Application.get_env(:sports_coach_bookings, __MODULE__, [])
  end

  defp fetch!(config, key) do
    case Keyword.get(config, key) do
      nil -> raise ArgumentError, "missing S3 config #{inspect(key)} for #{inspect(__MODULE__)}"
      value -> value
    end
  end

  defp host_and_path(config, key) do
    encoded_key = encode_path(key)

    case Keyword.get(config, :endpoint) do
      nil ->
        region = fetch!(config, :region)
        bucket = fetch!(config, :bucket)
        {"https", "#{bucket}.s3.#{region}.amazonaws.com", "/#{encoded_key}"}

      endpoint ->
        uri = URI.parse(endpoint)
        bucket = fetch!(config, :bucket)

        path =
          if Keyword.get(config, :force_path_style, true) do
            "/#{bucket}/#{encoded_key}"
          else
            "/#{encoded_key}"
          end

        {uri.scheme || "https", uri.host, path}
    end
  end

  defp base_url(config) do
    case Keyword.get(config, :endpoint) do
      nil ->
        region = fetch!(config, :region)
        bucket = fetch!(config, :bucket)
        "https://#{bucket}.s3.#{region}.amazonaws.com"

      endpoint ->
        uri = URI.parse(endpoint)
        bucket = fetch!(config, :bucket)

        if Keyword.get(config, :force_path_style, true) do
          "#{uri.scheme || "https"}://#{uri.host}/#{bucket}"
        else
          "#{uri.scheme || "https"}://#{bucket}.#{uri.host}"
        end
    end
  end

  # --- signing --------------------------------------------------------------

  defp canonical_query(params) do
    params
    |> Enum.map(fn {k, v} -> {encode(k), encode(v)} end)
    |> Enum.sort()
    |> Enum.map_join("&", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp signing_key(secret, date, region, service) do
    ("AWS4" <> secret)
    |> hmac(date)
    |> hmac(region)
    |> hmac(service)
    |> hmac("aws4_request")
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  defp sha256_hex(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp amz_date(%DateTime{} = now) do
    now
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace(~r/[-:]/, "")
    |> String.replace_suffix("Z", "Z")
  end

  defp encode(term) when is_binary(term) do
    term
    |> :binary.bin_to_list()
    |> Enum.map_join(&encode_byte/1)
  end

  # Percent-encode each path segment but keep the `/` separators (RFC 3986 path).
  defp encode_path(key) do
    key
    |> String.split("/")
    |> Enum.map_join("/", &encode/1)
  end

  defp encode_byte(byte)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?-, ?_, ?., ?~],
       do: <<byte>>

  defp encode_byte(byte), do: "%" <> Base.encode16(<<byte>>, case: :upper)

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
