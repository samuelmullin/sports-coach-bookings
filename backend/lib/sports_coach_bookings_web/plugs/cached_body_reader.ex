defmodule SportsCoachBookingsWeb.Plugs.CachedBodyReader do
  @moduledoc """
  Reads and caches the request body so signature-verified webhooks can HMAC the
  exact bytes the provider signed.

  Configured as `Plug.Parsers`' `:body_reader`; the raw body is available in the
  controller as `conn.assigns.raw_body`.
  """

  @doc "Reads the body and stashes a copy in `conn.assigns.raw_body`."
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}
  end
end
