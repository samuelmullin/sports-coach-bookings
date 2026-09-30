defmodule SportsCoachBookingsWeb.TenancyJSON do
  @moduledoc "Serialises tenants, settings, and branding."

  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Tenancy.Branding

  @doc "Serialises a tenant."
  @spec tenant(Tenant.t()) :: map()
  def tenant(%Tenant{} = tenant) do
    %{
      id: tenant.id,
      name: tenant.name,
      slug: tenant.slug,
      status: tenant.status,
      timezone: tenant.timezone,
      currency: tenant.currency,
      contact_email: tenant.contact_email
    }
  end

  @doc "Serialises tenant settings with the derived `currency_locked` flag."
  @spec settings(%{tenant: Tenant.t(), currency_locked: boolean()}) :: map()
  def settings(%{tenant: tenant, currency_locked: locked}) do
    %{tenant: tenant(tenant), currency_locked: locked}
  end

  @doc "Serialises a branding row, including public asset URLs and warnings."
  @spec branding(Branding.t(), [String.t()]) :: map()
  def branding(%Branding{} = branding, warnings \\ []) do
    %{
      id: branding.id,
      logo_key: branding.logo_key,
      favicon_key: branding.favicon_key,
      logo_url: Branding.asset_url(branding.logo_key),
      favicon_url: Branding.asset_url(branding.favicon_key),
      primary_color: branding.primary_color,
      secondary_color: branding.secondary_color,
      accent_color: branding.accent_color,
      background_color: branding.background_color,
      text_color: branding.text_color,
      font_family: branding.font_family,
      email_footer_text: branding.email_footer_text,
      social_links: branding.social_links,
      warnings: warnings
    }
  end
end
