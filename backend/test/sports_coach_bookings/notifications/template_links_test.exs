defmodule SportsCoachBookings.Notifications.TemplateLinksTest do
  @moduledoc """
  Token links in transactional email must open the right SPA route on the right
  host: customer links on the tenant's host, staff links on the platform host's
  `/admin` app. Regression for confirmation emails that pointed at the platform
  host with a route (`/confirm`) the portal does not have.
  """

  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Notifications

  @token "tok_abc-123"

  setup do
    tenant = insert(:tenant, slug: "links-acme")
    put_tenant(tenant)
    host = "#{tenant.slug}.#{Application.fetch_env!(:sports_coach_bookings, :base_domain)}"
    scheme = Application.fetch_env!(:sports_coach_bookings, :notifications_url_scheme)
    platform = Application.fetch_env!(:sports_coach_bookings, :notifications_app_url)
    %{tenant: tenant, tenant_base: "#{scheme}://#{host}", platform: platform}
  end

  defp rendered(template, assigns, tenant) do
    {:ok, %{html: html, text: text}} =
      Notifications.render(template, assigns, tenant_id: tenant.id)

    html <> "\n" <> text
  end

  test "customer links use the tenant host and the portal's routes", %{
    tenant: tenant,
    tenant_base: base
  } do
    cases = [
      {:customer_confirm, %{email: "a@example.com", token: @token},
       "/confirm-email?token=#{@token}"},
      {:customer_reset_password, %{email: "a@example.com", token: @token},
       "/reset-password?token=#{@token}"},
      {:customer_email_change,
       %{email: "a@example.com", previous_email: "b@example.com", token: @token},
       "/confirm-email?token=#{@token}"},
      {:household_invite,
       %{email: "a@example.com", relationship: "Parent", token: @token, tenant: "Acme"},
       "/accept-invite/#{@token}"}
    ]

    for {template, assigns, path} <- cases do
      assert rendered(template, assigns, tenant) =~ base <> path,
             "#{template} should link to #{base}#{path}"
    end
  end

  test "staff links use the platform host's admin app", %{tenant: tenant, platform: platform} do
    cases = [
      {:staff_confirm, %{email: "s@example.com", token: @token},
       "/admin/confirm-email?token=#{@token}"},
      {:staff_reset_password, %{email: "s@example.com", token: @token},
       "/admin/reset-password?token=#{@token}"},
      {:staff_invite, %{email: "s@example.com", role: "coach", token: @token, tenant: "Acme"},
       "/admin/accept-invite/#{@token}"}
    ]

    for {template, assigns, path} <- cases do
      assert rendered(template, assigns, tenant) =~ platform <> path,
             "#{template} should link to #{platform}#{path}"
    end
  end

  test "tokens are URL-encoded", %{tenant: tenant, tenant_base: base} do
    out = rendered(:customer_confirm, %{email: "a@example.com", token: "a b+c/d"}, tenant)
    assert out =~ base <> "/confirm-email?token=a+b%2Bc%2Fd"
  end
end
