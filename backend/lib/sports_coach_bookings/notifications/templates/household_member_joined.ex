defmodule SportsCoachBookings.Notifications.Templates.HouseholdMemberJoined do
  @moduledoc "A co-manager joined a household. `:household_member_joined`."

  use SportsCoachBookings.Notifications.Template,
    required: [],
    subject: "A co-manager joined your household",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">New co-manager</h1>
    <p style="margin:0 0 16px 0;"><%= assigns[:member_email] || "A new co-manager" %> has joined your household and can help manage players and bookings.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View household", assigns[:household_url]) %>
    """,
    text: """
    New co-manager

    <%= assigns[:member_email] || "A new co-manager" %> has joined your household and can help manage players and bookings.

    View household: <%= assigns[:household_url] %>
    """,
    sample: %{
      member_email: "co-manager@example.com",
      household_url: "https://localhost/portal/household"
    }
end
