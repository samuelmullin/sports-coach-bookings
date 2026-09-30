defmodule SportsCoachBookings.Notifications.Templates.StaffJoined do
  @moduledoc "A staff member joined the tenant. `:staff_joined`."

  use SportsCoachBookings.Notifications.Template,
    required: [:role],
    subject: "New team member joined",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">New team member</h1>
    <p style="margin:0 0 16px 0;"><%= assigns[:member_email] || "A new member" %> has joined the team as <strong><%= assigns[:role] %></strong>.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View team", assigns[:team_url]) %>
    """,
    text: """
    New team member

    <%= assigns[:member_email] || "A new member" %> has joined the team as <%= assigns[:role] %>.

    View team: <%= assigns[:team_url] %>
    """,
    sample: %{
      role: "coach",
      member_email: "coach@example.com",
      team_url: "https://localhost/admin/team"
    }
end
