defmodule SportsCoachBookings.Notifications.Templates.StaffInvite do
  @moduledoc "Staff invitation template. Registered as `:staff_invite`."

  use SportsCoachBookings.Notifications.Template,
    required: [:email, :role, :token],
    subject: "You are invited to join <%= assigns[:tenant] || ~s(the team) %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">You are invited to join the team</h1>
    <p style="margin:0 0 16px 0;"><%= assigns[:tenant] || "A coaching provider" %> has invited you to join as a <strong><%= assigns[:role] %></strong>.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Accept invitation", SportsCoachBookings.Notifications.Templates.Helpers.admin_path_link("/accept-invite", assigns[:token])) %>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">This invitation expires in 7 days.</p>
    """,
    text: """
    You are invited to join the team

    <%= assigns[:tenant] || "A coaching provider" %> has invited you to join as a <%= assigns[:role] %>.

    <%= SportsCoachBookings.Notifications.Templates.Helpers.admin_path_link("/accept-invite", assigns[:token]) %>

    This invitation expires in 7 days.
    """
end
