defmodule SportsCoachBookingsWeb.Plugs.RateLimit do
  @moduledoc """
  Rate-limits a request by client IP and, optionally, an account identifier
  (e.g. the submitted email) plus the resolved tenant.

  Enforcement uses `SportsCoachBookings.RateLimiter` (ETS, fixed window). The
  hook point was left by wp-01/wp-02 (see
  `docs/rfcs/20260928-customers-rate-limit-hook.md`); wp-19 implements it.

  Options:

    * `:limit` — max hits per window (default 60).
    * `:window` — window length in seconds (default 60).
    * `:account_param` — a request param whose value is also used as a key
      (e.g. `"email"`), so per-account brute force is limited even from
      rotating IPs.
    * `:keys` — extra static key parts (atoms/strings), e.g. `[:login]`.

  On limit, halts with `429` and the standard error envelope
  (`code: "too_many_requests"`) plus a `Retry-After` header.
  """

  @behaviour Plug

  import Plug.Conn

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.RateLimiter

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    if RateLimiter.enabled?() do
      enforce(conn, opts)
    else
      conn
    end
  end

  defp enforce(conn, opts) do
    limit = Keyword.get(opts, :limit, 60)
    window = Keyword.get(opts, :window, 60)
    keys = keys(conn, opts)

    case RateLimiter.hit(keys, limit, window) do
      :ok ->
        conn

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{
            error: %{
              code: "too_many_requests",
              message: "Too many requests",
              details: %{"retry_after" => retry_after}
            }
          })
        )
        |> halt()
    end
  end

  defp keys(conn, opts) do
    # Scope prefixes every key so buckets for different routes never collide.
    prefix =
      case Keyword.get(opts, :keys, []) do
        [] -> ""
        scope -> Enum.map_join(scope, "-", &to_string/1) <> "|"
      end

    ip = prefix <> "ip:" <> client_ip(conn)

    # Only include the tenant when one is resolved: on the platform host every
    # request would otherwise share one global bucket.
    tenant =
      case TenantContext.get_tenant_id() do
        nil -> []
        id -> [prefix <> "tenant:" <> id]
      end

    account =
      case Keyword.get(opts, :account_param) do
        nil -> []
        param -> account_key(conn, param, prefix)
      end

    [ip | tenant] ++ account
  end

  defp account_key(conn, param, prefix) do
    case param_value(conn, param) do
      value when is_binary(value) and value != "" -> [prefix <> "acct:" <> String.downcase(value)]
      _ -> []
    end
  end

  defp param_value(conn, param) do
    params = conn.params

    cond do
      is_binary(Map.get(params, param)) -> Map.get(params, param)
      is_map(Map.get(params, "session")) -> Map.get(params["session"], param)
      true -> nil
    end
  end

  @doc """
  The client IP used for limiting.

  On Fly.io the edge proxy sets `fly-client-ip` to the real client address and
  strips client-supplied values; prefer it over `x-forwarded-for` (which is
  spoofable). Falls back to the socket peer for local/dev.
  """
  @spec client_ip(Plug.Conn.t()) :: String.t()
  def client_ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] when is_binary(ip) and ip != "" ->
        ip

      _ ->
        case get_req_header(conn, "x-forwarded-for") do
          [forwarded | _] when is_binary(forwarded) and forwarded != "" ->
            forwarded |> String.split(",") |> List.first() |> String.trim()

          _ ->
            conn.remote_ip |> :inet.ntoa() |> to_string()
        end
    end
  end
end
