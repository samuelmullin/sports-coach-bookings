defmodule SportsCoachBookings.Notifications.Templates.Helpers do
  @moduledoc """
  Shared helpers callable from template EEx (fully qualified) to build links.

  Tenancy is host-based, so every customer-facing link must point at the
  **tenant's own host** (`<slug>.<base_domain>`), where the portal SPA and the
  tenant-scoped API live. Staff accounts are platform-wide, so staff links
  point at the platform host's admin app (`/admin/...`). Paths mirror the SPA
  routes in `frontend/apps/portal` and `frontend/apps/admin`.
  """

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Tenancy

  @doc "Platform base URL (`:notifications_app_url`), used when no tenant applies."
  @spec app_url() :: String.t()
  def app_url do
    Application.get_env(
      :sports_coach_bookings,
      :notifications_app_url,
      "https://sportscoachbookings.com"
    )
  end

  @doc """
  Absolute URL for `path` on the tenant's host. With no tenant (`nil`) or an
  unknown one it falls back to the platform base URL.
  """
  @spec tenant_url(binary() | nil, String.t()) :: String.t()
  def tenant_url(nil, path), do: app_url() <> path

  def tenant_url(tenant_id, path) do
    case Tenancy.get_tenant(tenant_id) do
      %{slug: slug} -> "#{scheme()}://#{slug}.#{base_domain()}#{port()}#{path}"
      _ -> app_url() <> path
    end
  end

  @doc "A portal link (tenant host, tenant from context) carrying `?token=`."
  @spec portal_link(String.t(), String.t()) :: String.t()
  def portal_link(path, token),
    do: tenant_url(TenantContext.get_tenant_id(), path) <> token_query(token)

  @doc "A portal link whose token is a path segment, e.g. `/accept-invite/<token>`."
  @spec portal_path_link(String.t(), String.t()) :: String.t()
  def portal_path_link(path, token),
    do:
      tenant_url(
        TenantContext.get_tenant_id(),
        "#{path}/#{URI.encode_www_form(to_string(token))}"
      )

  @doc "An admin-app link on the platform host, carrying `?token=`."
  @spec admin_link(String.t(), String.t()) :: String.t()
  def admin_link(path, token), do: app_url() <> "/admin" <> path <> token_query(token)

  @doc "An admin-app link on the platform host whose token is a path segment."
  @spec admin_path_link(String.t(), String.t()) :: String.t()
  def admin_path_link(path, token),
    do: app_url() <> "/admin" <> "#{path}/#{URI.encode_www_form(to_string(token))}"

  @doc "Renders a simple email button linking to `url`."
  @spec button(String.t(), String.t()) :: String.t()
  def button(label, url) do
    ~s(<p style="margin:24px 0;"><a href="#{url}" style="background-color:#1d4ed8;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:6px;display:inline-block;font-weight:bold;">#{label}</a></p>)
  end

  defp token_query(token), do: "?token=" <> URI.encode_www_form(to_string(token))

  defp scheme,
    do: Application.get_env(:sports_coach_bookings, :notifications_url_scheme, "https")

  defp base_domain,
    do: Application.get_env(:sports_coach_bookings, :base_domain, "sportscoachbookings.com")

  # Only set in local development (e.g. 4000); production hosts use the default port.
  defp port do
    case Application.get_env(:sports_coach_bookings, :notifications_url_port) do
      nil -> ""
      port -> ":#{port}"
    end
  end
end
