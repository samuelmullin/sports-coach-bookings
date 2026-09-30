defmodule SportsCoachBookingsWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Adds browser security headers to every response (WP-19).

  Applied at the endpoint so it covers API, webhook, health and SPA responses
  alike. The API is JSON-only and Stripe Checkout is a redirect, so scripts only
  need to come from our own origin. HSTS is added by `force_ssl` in production.
  """

  @behaviour Plug
  @headers %{
    "content-security-policy" =>
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " <>
        "img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https:; " <>
        "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
    "x-frame-options" => "DENY",
    "x-content-type-options" => "nosniff",
    "referrer-policy" => "strict-origin-when-cross-origin",
    "permissions-policy" => "camera=(), microphone=(), geolocation=()",
    "cross-origin-opener-policy" => "same-origin"
  }

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Enum.reduce(@headers, conn, fn {name, value}, conn ->
      Plug.Conn.put_resp_header(conn, name, value)
    end)
  end
end
