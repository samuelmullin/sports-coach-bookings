defmodule SportsCoachBookingsWeb.SafeRedirect do
  @moduledoc """
  Validates post-provider redirect URLs (WP-19).

  Stripe onboarding accepts a `return_url`/`refresh_url`. To prevent an open
  redirect, only same-site `https` URLs (or `http` on localhost) are passed
  through; anything else returns `nil` so the caller can fall back to a
  configured default.
  """

  @spec sanitize(binary() | nil) :: binary() | nil
  def sanitize(nil), do: nil

  def sanitize(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if same_site?(host, scheme), do: url, else: nil

      _ ->
        nil
    end
  end

  def sanitize(_url), do: nil

  @doc "True when `host` belongs to the configured tenant base domain or localhost."
  @spec same_site?(binary(), binary()) :: boolean()
  def same_site?(host, scheme) do
    local = host in ["localhost", "127.0.0.1", "::1"]
    domain = base_domain()

    cond do
      local -> scheme in ["http", "https"]
      scheme != "https" -> false
      host == domain -> true
      String.ends_with?(host, "." <> domain) -> true
      true -> false
    end
  end

  defp base_domain do
    Application.get_env(:sports_coach_bookings, :base_domain, "sportscoachbookings.com")
  end
end
