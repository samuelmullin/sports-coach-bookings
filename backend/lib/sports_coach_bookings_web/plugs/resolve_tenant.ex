defmodule SportsCoachBookingsWeb.Plugs.ResolveTenant do
  @moduledoc """
  Resolves the tenant from the request host and puts it in the process context.

  The tenant is **only ever** resolved from the `Host` header. Requests to the
  platform (apex) host or bare localhost pass through with no tenant. A request
  to a subdomain that does not map to an active tenant is halted with `404`.
  """

  import Ecto.Query
  import Plug.Conn

  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Core.TenantDomain
  alias SportsCoachBookings.Repo

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    host = conn.host

    if platform_host?(host) do
      conn
    else
      resolve(conn, host)
    end
  end

  defp resolve(conn, host) do
    case fetch_tenant(host) do
      %Tenant{} = tenant ->
        TenantContext.put_tenant(tenant)
        Logger.metadata(tenant_id: tenant.slug)
        assign(conn, :tenant, tenant)

      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          404,
          Jason.encode!(%{
            error: %{code: "tenant_not_found", message: "Unknown tenant for host"}
          })
        )
        |> halt()
    end
  end

  defp fetch_tenant(host) do
    slug = slug_for(host)

    from(t in Tenant,
      where: t.status == :active,
      where:
        t.slug == ^slug or
          t.id in subquery(from(d in TenantDomain, where: d.host == ^host, select: d.tenant_id)),
      limit: 1
    )
    |> Repo.one(skip_tenant: true)
  end

  defp slug_for(host) do
    base = base_domain()

    cond do
      host == base -> nil
      String.ends_with?(host, "." <> base) -> String.replace_suffix(host, "." <> base, "")
      true -> host
    end
  end

  defp platform_host?(host) do
    host in [platform_host(), base_domain(), "localhost", "127.0.0.1", "::1"]
  end

  defp base_domain,
    do: Application.get_env(:sports_coach_bookings, :base_domain, "sportscoachbookings.com")

  defp platform_host do
    Application.get_env(:sports_coach_bookings, :platform_host, "sportscoachbookings.com")
  end
end
