defmodule SportsCoachBookings.Websites.Content do
  @moduledoc """
  Server-side validation of hosted-site content. The editor is untrusted input:
  the portal renders whatever is published, so size, link targets and asset
  keys are enforced here rather than only in the SPA.
  """

  @max_bytes 256_000
  @max_depth 8
  @max_string 5_000
  @link_fields ~w(url href link primary_cta_url secondary_cta_url cta_url)

  @doc "Returns `:ok` or `{:error, message}` for a content map owned by `tenant_id`."
  @spec validate(term(), binary() | nil) :: :ok | {:error, binary()}
  def validate(content, tenant_id) when is_map(content) do
    with :ok <- check_size(content), do: walk(content, tenant_id, 0)
  end

  def validate(_content, _tenant_id), do: {:error, "must be an object"}

  @doc "True for same-site absolute paths and http(s) URLs only."
  @spec safe_link?(term()) :: boolean()
  def safe_link?(""), do: true

  def safe_link?(value) when is_binary(value) do
    cond do
      String.starts_with?(value, "//") -> false
      String.starts_with?(value, "/") -> not String.contains?(value, ["\\", "\n", "\r"])
      true -> http_url?(value)
    end
  end

  def safe_link?(_value), do: false

  defp http_url?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _other ->
        false
    end
  end

  defp check_size(content) do
    if byte_size(Jason.encode!(content)) > @max_bytes,
      do: {:error, "is too large"},
      else: :ok
  end

  defp walk(_value, _tenant_id, depth) when depth > @max_depth,
    do: {:error, "is nested too deeply"}

  defp walk(value, tenant_id, depth) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {key, child}, :ok ->
      case field(to_string(key), child, tenant_id, depth) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp walk(value, tenant_id, depth) when is_list(value) do
    Enum.reduce_while(value, :ok, fn child, :ok ->
      case walk(child, tenant_id, depth + 1) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp walk(value, _tenant_id, _depth) when is_binary(value) do
    if String.length(value) > @max_string,
      do: {:error, "contains text that is too long"},
      else: :ok
  end

  defp walk(_value, _tenant_id, _depth), do: :ok

  defp field(key, value, _tenant_id, _depth) when key in @link_fields do
    if safe_link?(value), do: :ok, else: {:error, "#{key} must be a site path or http(s) link"}
  end

  defp field(key, value, tenant_id, _depth) when is_binary(value) do
    if String.ends_with?(key, "_key"),
      do: asset_key(key, value, tenant_id),
      else: walk(value, tenant_id, 0)
  end

  defp field(_key, value, tenant_id, depth), do: walk(value, tenant_id, depth + 1)

  defp asset_key(_key, "", _tenant_id), do: :ok

  defp asset_key(key, value, tenant_id) do
    if is_binary(tenant_id) and String.starts_with?(value, tenant_id <> "/") and
         not String.contains?(value, ["..", "\\"]),
       do: :ok,
       else: {:error, "#{key} must reference one of this club's uploads"}
  end
end
