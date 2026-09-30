defmodule SportsCoachBookings.Notifications.Templates.BookingAttended do
  @moduledoc "Attendance confirmation. `:booking_attended`."

  use SportsCoachBookings.Notifications.Template,
    required: [:player_name, :offering_name],
    subject: "<%= assigns[:player_name] %> attended <%= assigns[:offering_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Thanks for coming</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:player_name] %></strong> has been marked present for <strong><%= assigns[:offering_name] %></strong>.</p>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">Your coach may share feedback from the session soon.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View player", assigns[:manage_url]) %>
    """,
    text: """
    Thanks for coming

    <%= assigns[:player_name] %> has been marked present for <%= assigns[:offering_name] %>.

    Your coach may share feedback from the session soon.

    View player: <%= assigns[:manage_url] %>
    """,
    sample: %{
      player_name: "Riley",
      offering_name: "U12 Skills",
      manage_url: "https://localhost/portal"
    }
end
