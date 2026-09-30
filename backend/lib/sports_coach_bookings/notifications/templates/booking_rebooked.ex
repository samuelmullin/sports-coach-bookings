defmodule SportsCoachBookings.Notifications.Templates.BookingRebooked do
  @moduledoc "Old → new booking with an updated calendar attachment. `:booking_rebooked`."

  use SportsCoachBookings.Notifications.Template,
    required: [:player_name, :from_starts_at, :to_starts_at],
    subject: "Booking moved for <%= assigns[:player_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Booking moved</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:player_name] %></strong>'s <%= assigns[:offering_name] %> booking has moved.</p>
    <p style="margin:0 0 16px 0;">
      <span style="color:#6b7280;">From:</span> <%= assigns[:from_starts_at] %><br />
      <span style="color:#6b7280;">To:</span> <strong><%= assigns[:to_starts_at] %></strong>
    </p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View booking", assigns[:manage_url]) %>
    <p style="margin:0;color:#6b7280;font-size:14px;">The attached calendar invitation replaces the previous one (same event).</p>
    """,
    text: """
    Booking moved

    <%= assigns[:player_name] %>'s <%= assigns[:offering_name] %> booking has moved.

    From: <%= assigns[:from_starts_at] %>
    To: <%= assigns[:to_starts_at] %>

    View booking: <%= assigns[:manage_url] %>

    The attached calendar invitation replaces the previous one (same event).
    """,
    sample: %{
      player_name: "Riley",
      offering_name: "U12 Skills",
      from_starts_at: "Tue, 6 Jan 2026 at 5:00 PM",
      to_starts_at: "Thu, 8 Jan 2026 at 5:00 PM",
      manage_url: "https://localhost/portal/bookings/sample"
    }
end
