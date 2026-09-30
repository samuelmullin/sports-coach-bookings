defmodule SportsCoachBookingsWeb.Plugs.VerifyOrigin do
  @moduledoc """
  Same-site `Origin` check for state-changing API requests (WP-19).

  The API is cookie-authenticated (staff and portal sessions) and JSON-only.
  Session cookies are `SameSite=Lax`, so browsers do not attach them to
  cross-site `POST`/`PUT`/`PATCH`/`DELETE`. This plug is defence in depth: when a
  browser sends an `Origin` header on a state-changing request, it must match the
  request host (or a localhost dev origin). Requests without an `Origin` (CLI,
  webhooks, server-to-server) pass through; the cookie still cannot be attached
  cross-site because of `SameSite=Lax`.

  Halts with `403 forbidden` when the origin does not match.
  """

  @behaviour Plug

  import Plug.Conn

  @state_changing ~w(POST PUT PATCH DELETE)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if conn.method in @state_changing do
      check(conn)
    else
      conn
    end
  end

  defp check(conn) do
    case get_req_header(conn, "origin") do
      [] -> conn
      [origin | _] -> if allowed?(origin, conn), do: conn, else: reject(conn)
    end
  end

  defp allowed?(origin, conn) do
    case URI.parse(origin) do
      %URI{host: host} when is_binary(host) and host != "" ->
        host == conn.host or host in ["localhost", "127.0.0.1", "::1"]

      _ ->
        false
    end
  end

  defp reject(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      403,
      Jason.encode!(%{
        error: %{code: "forbidden", message: "Cross-origin request rejected", details: %{}}
      })
    )
    |> halt()
  end
end
