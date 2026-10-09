defmodule SportsCoachBookings.Notifications.Templates.PrivateSessionRequestReviewed do
  @moduledoc "Decision notice for a customer-requested private session."

  use SportsCoachBookings.Notifications.Template,
    required: [:offering, :player_count, :status],
    subject: "Your private session request was <%= assigns[:status] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Private session request <%= assigns[:status] %></h1>
    <p style="margin:0 0 16px 0;">Your request for <strong><%= assigns[:offering] %></strong> for <%= assigns[:player_count] %> player<%= if assigns[:player_count] == 1, do: "", else: "s" %> was <%= assigns[:status] %>.</p>
    <%= if assigns[:starts_at] do %><p style="margin:0 0 16px 0;">Scheduled for <%= assigns[:starts_at] %>.</p><% end %>
    <%= if assigns[:decline_reason] do %><p style="margin:0 0 16px 0;">Reason: <%= assigns[:decline_reason] %></p><% end %>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View private requests", SportsCoachBookings.Notifications.Templates.Helpers.portal_url("/private-session-requests")) %>
    """,
    text: """
    Your private session request for <%= assigns[:offering] %> for <%= assigns[:player_count] %> player(s) was <%= assigns[:status] %>.
    <%= if assigns[:starts_at], do: "Scheduled for " <> assigns[:starts_at] <> "." %>
    <%= if assigns[:decline_reason], do: "Reason: " <> assigns[:decline_reason] %>

    <%= SportsCoachBookings.Notifications.Templates.Helpers.portal_url("/private-session-requests") %>
    """
end
