defmodule SportsCoachBookings.Notifications.Templates.SessionInvite do
  @moduledoc "Invitation to join another household's coaching session."

  use SportsCoachBookings.Notifications.Template,
    required: [:email, :token, :offering, :starts_at, :payment_mode],
    subject: "You're invited to a coaching session",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">You're invited</h1>
    <p style="margin:0 0 16px 0;">A player has invited you to join <strong><%= assigns[:offering] %></strong> on <%= assigns[:starts_at] %>.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View invitation", SportsCoachBookings.Notifications.Templates.Helpers.portal_path_link("/session-invites", assigns[:token])) %>
    <p style="margin:16px 0 0 0;color:#6b7280;font-size:14px;"><%= if assigns[:payment_mode] == "organizer", do: "The organizer is covering your space.", else: "You will pay your own share when you accept." %></p>
    <%= if assigns[:expires_at] do %><p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;">The reserved space expires at <%= assigns[:expires_at] %>.</p><% end %>
    """,
    text: """
    You're invited to join <%= assigns[:offering] %> on <%= assigns[:starts_at] %>.

    <%= SportsCoachBookings.Notifications.Templates.Helpers.portal_path_link("/session-invites", assigns[:token]) %>

    <%= if assigns[:payment_mode] == "organizer", do: "The organizer is covering your space.", else: "You will pay your own share when you accept." %>
    """
end
