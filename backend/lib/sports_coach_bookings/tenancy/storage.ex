defmodule SportsCoachBookings.Tenancy.Storage do
  @moduledoc """
  Object-storage behaviour for tenant assets (logos, favicons, coach photos).

  No S3 backend is configured in this environment. Branding uploads therefore go
  through this behaviour, whose default implementation is
  `SportsCoachBookings.Tenancy.Storage.Fake` (deterministic presigned-style URLs
  and keys). Swap the implementation with
  `config :sports_coach_bookings, :tenancy_storage, MyS3Storage`.

  See `docs/rfcs/20260928-tenancy-storage-stub.md`.
  """

  @max_bytes 2_000_000
  @allowed_content_types ~w(image/png image/jpeg image/webp image/svg+xml)

  alias SportsCoachBookings.Tenancy.Storage.Svg

  @type upload :: %{
          content_type: String.t(),
          byte_size: non_neg_integer(),
          filename: String.t() | nil
        }

  @type presigned :: %{
          key: String.t(),
          upload_url: String.t(),
          method: String.t(),
          headers: map(),
          expires_at: DateTime.t()
        }

  @callback presign_put(upload(), tenant_id :: binary()) ::
              {:ok, presigned()} | {:error, term()}
  @callback public_url(key :: binary()) :: String.t()

  @doc "The configured storage implementation."
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :sports_coach_bookings,
      :tenancy_storage,
      SportsCoachBookings.Tenancy.Storage.Fake
    )
  end

  @doc "Validates and presigns a PUT upload request."
  @spec presign_put(map(), binary()) :: {:ok, presigned()} | {:error, term()}
  def presign_put(attrs, tenant_id) do
    with {:ok, upload} <- validate(attrs) do
      impl().presign_put(upload, tenant_id)
    end
  end

  @doc "A public (read) URL for a stored key."
  @spec public_url(binary()) :: String.t()
  def public_url(key), do: impl().public_url(key)

  @doc "Maximum accepted upload size in bytes (2 MB)."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "Accepted upload content types."
  @spec allowed_content_types() :: [String.t()]
  def allowed_content_types, do: @allowed_content_types

  @doc """
  Validates an upload request's content type and size.

  When the request carries inline `content` (used by the dev/test stub, which
  cannot offload to S3), SVG payloads are sanitised with
  `SportsCoachBookings.Tenancy.Storage.Svg.sanitize/1`.
  """
  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(attrs) do
    attrs = normalize(attrs)

    with :ok <- validate_type(attrs.content_type),
         :ok <- validate_size(attrs.byte_size),
         :ok <- validate_content(attrs),
         :ok <- validate_svg(attrs) do
      {:ok, attrs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_type(content_type) when content_type in @allowed_content_types, do: :ok
  defp validate_type(_content_type), do: {:error, :unsupported_content_type}

  defp validate_size(size) when is_integer(size) and size > @max_bytes,
    do: {:error, :file_too_large}

  defp validate_size(size) when is_integer(size) and size > 0, do: :ok
  defp validate_size(_size), do: {:error, :invalid_byte_size}

  # Content-type sniffing: when the inline bytes are present (dev/test store),
  # the declared content type must match the magic bytes. For the S3 presigned
  # PUT the bytes never transit the app; the bucket policy + the signed
  # `Content-Type` header are the control (see docs/security-review.md).
  defp validate_content(%{content: content, content_type: content_type})
       when is_binary(content) and is_binary(content_type) do
    if matches_declared_type?(content, content_type),
      do: :ok,
      else: {:error, :content_type_mismatch}
  end

  defp validate_content(_attrs), do: :ok

  defp matches_declared_type?(content, "image/png"),
    do: match?(<<0x89, "PNG", _::binary>>, content)

  defp matches_declared_type?(content, "image/jpeg"),
    do: match?(<<0xFF, 0xD8, 0xFF, _::binary>>, content)

  defp matches_declared_type?(content, "image/webp"),
    do: match?(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>, content)

  defp matches_declared_type?(content, "image/svg+xml"), do: svg?(content)

  defp matches_declared_type?(_content, _content_type), do: false

  defp svg?(content) do
    content
    |> String.trim_leading()
    |> String.downcase()
    |> then(&(String.starts_with?(&1, "<?xml") or String.starts_with?(&1, "<svg")))
  end

  defp validate_svg(%{content_type: "image/svg+xml", content: content}) when is_binary(content) do
    case Svg.sanitize(content) do
      {:ok, _sanitized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_svg(_attrs), do: :ok

  defp normalize(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    %{
      content_type: attrs["content_type"],
      byte_size: attrs["byte_size"],
      filename: attrs["filename"],
      content: attrs["content"]
    }
  end
end
