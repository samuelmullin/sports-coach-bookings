defmodule SportsCoachBookings.Notifications.Templates.StaffRemoved do
  @moduledoc "A staff member left the tenant. `:staff_removed`."

  use SportsCoachBookings.Notifications.Template,
    required: [:role],
    subject: "A team member was removed",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Team member removed</h1>
    <p style="margin:0 0 16px 0;"><%= assigns[:member_email] || "A team member" %> (role: <strong><%= assigns[:role] %></strong>) has been removed from the team.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View team", assigns[:team_url]) %>
    """,
    text: """
    Team member removed

    <%= assigns[:member_email] || "A team member" %> (role: <%= assigns[:role] %>) has been removed from the team.

    View team: <%= assigns[:team_url] %>
    """,
    sample: %{
      role: "coach",
      member_email: "coach@example.com",
      team_url: "https://localhost/admin/team"
    }
end
