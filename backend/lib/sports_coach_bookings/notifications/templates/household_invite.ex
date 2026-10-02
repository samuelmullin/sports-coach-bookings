defmodule SportsCoachBookings.Notifications.Templates.HouseholdInvite do
  @moduledoc "Household co-manager invitation template. Registered as `:household_invite`."

  use SportsCoachBookings.Notifications.Template,
    required: [:email, :token],
    subject: "You have been invited to join a household",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">You have been invited</h1>
    <p style="margin:0 0 16px 0;"><%= assigns[:tenant] || "A coaching provider" %> has invited you to co-manage a household<%= if assigns[:relationship] do %> as a <strong><%= assigns[:relationship] %></strong><% end %>.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Accept invitation", SportsCoachBookings.Notifications.Templates.Helpers.portal_path_link("/accept-invite", assigns[:token])) %>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">This invitation expires in 7 days.</p>
    """,
    text: """
    You have been invited

    <%= assigns[:tenant] || "A coaching provider" %> has invited you to co-manage a household.

    <%= SportsCoachBookings.Notifications.Templates.Helpers.portal_path_link("/accept-invite", assigns[:token]) %>

    This invitation expires in 7 days.
    """
end
