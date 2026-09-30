defmodule SportsCoachBookings.Notifications.Layout do
  @moduledoc """
  The single responsive HTML email layout.

  Styles are authored inline (`style="…"`) so they survive email clients, with a
  small `<style>` block only for the responsive media query. The layout renders
  the tenant logo, primary colour, footer text, social links, and — for
  non-transactional mail — a one-click unsubscribe link.

  See `docs/rfcs/20260928-notifications-engine.md` for why there is no external
  premailer dependency.
  """

  alias SportsCoachBookings.Notifications.Render

  @default_primary "#1d4ed8"
  @default_background "#f4f5f7"
  @default_text "#111827"

  @doc """
  Wraps `inner_html` (produced by a template) in the shared layout.

  `branding` is the map returned by `SportsCoachBookings.Tenancy.branding_for_email/1`.
  Options: `:contact_email`, `:show_unsubscribe`, `:unsubscribe_url`,
  `:category`.
  """
  @spec render(String.t(), map(), keyword()) :: String.t()
  def render(inner_html, branding, opts \\ []) when is_binary(inner_html) do
    assigns = %{
      inner_html: inner_html,
      tenant_name: branding[:tenant_name] || "SportsCoachBookings",
      logo_url: branding[:logo_url],
      primary_color: branding[:primary_color] || @default_primary,
      accent_color: branding[:accent_color] || branding[:primary_color] || @default_primary,
      background_color: branding[:background_color] || @default_background,
      text_color: branding[:text_color] || @default_text,
      footer_text: branding[:email_footer_text],
      social_links: branding[:social_links] || %{},
      contact_email: opts[:contact_email],
      category: opts[:category],
      show_unsubscribe: opts[:show_unsubscribe] || false,
      unsubscribe_url: opts[:unsubscribe_url]
    }

    Render.eex(layout(), assigns)
  end

  defp layout do
    ~S"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="x-apple-disable-message-reformatting" />
        <title><%= assigns[:tenant_name] %></title>
        <style>
          @media only screen and (max-width: 600px) {
            .scb-container { width: 100% !important; }
            .scb-px { padding-left: 20px !important; padding-right: 20px !important; }
          }
        </style>
      </head>
      <body style="margin:0;padding:0;background-color:<%= assigns[:background_color] %>;font-family:Arial,Helvetica,sans-serif;color:<%= assigns[:text_color] %>;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:<%= assigns[:background_color] %>;padding:24px 0;">
          <tr>
            <td align="center">
              <table role="presentation" class="scb-container" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:600px;background-color:#ffffff;border-radius:8px;overflow:hidden;">
                <tr>
                  <td class="scb-px" style="background-color:<%= assigns[:primary_color] %>;padding:24px 32px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td align="left" style="vertical-align:middle;">
                          <%= if assigns[:logo_url] do %>
                            <img src="<%= assigns[:logo_url] %>" alt="<%= assigns[:tenant_name] %>" height="36" style="height:36px;display:block;border:0;" />
                          <% else %>
                            <span style="color:#ffffff;font-size:20px;font-weight:bold;"><%= assigns[:tenant_name] %></span>
                          <% end %>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td class="scb-px" style="padding:32px;font-size:16px;line-height:1.6;color:#111827;">
                    <%= assigns[:inner_html] %>
                  </td>
                </tr>
                <tr>
                  <td class="scb-px" style="background-color:#f9fafb;padding:24px 32px;font-size:12px;line-height:1.5;color:#6b7280;border-top:1px solid #e5e7eb;">
                    <p style="margin:0 0 8px 0;font-weight:bold;color:#374151;"><%= assigns[:tenant_name] %></p>
                    <%= if assigns[:footer_text] do %>
                      <p style="margin:0 0 8px 0;"><%= assigns[:footer_text] %></p>
                    <% end %>
                    <%= if assigns[:contact_email] do %>
                      <p style="margin:0 0 8px 0;">Contact: <a href="mailto:<%= assigns[:contact_email] %>" style="color:<%= assigns[:primary_color] %>;"><%= assigns[:contact_email] %></a></p>
                    <% end %>
                    <%= if map_size(assigns[:social_links]) > 0 do %>
                      <p style="margin:0 0 8px 0;">
                        <%= for {network, url} <- assigns[:social_links] do %>
                          <a href="<%= url %>" style="color:<%= assigns[:primary_color] %>;margin-right:12px;"><%= network %></a>
                        <% end %>
                      </p>
                    <% end %>
                    <%= if assigns[:show_unsubscribe] and assigns[:unsubscribe_url] do %>
                      <p style="margin:0 0 8px 0;">
                        <a href="<%= assigns[:unsubscribe_url] %>" style="color:<%= assigns[:primary_color] %>;">Unsubscribe</a>
                      </p>
                    <% end %>
                    <p style="margin:0;color:#9ca3af;">You are receiving this email because you have an account with <%= assigns[:tenant_name] %>.</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end
end
