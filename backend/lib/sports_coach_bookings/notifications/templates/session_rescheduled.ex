defmodule SportsCoachBookings.Notifications.Templates.SessionRescheduled do
  @moduledoc "Session moved to a new time or venue. `:session_rescheduled`."

  use SportsCoachBookings.Notifications.Template,
    required: [:offering_name, :from_starts_at, :to_starts_at],
    subject: "Session rescheduled: <%= assigns[:offering_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Session rescheduled</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:offering_name] %></strong> has a new time.</p>
    <p style="margin:0 0 16px 0;">
      <span style="color:#6b7280;">From:</span> <%= assigns[:from_starts_at] %><br />
      <span style="color:#6b7280;">To:</span> <strong><%= assigns[:to_starts_at] %></strong><%= if assigns[:venue_name], do: " at " <> assigns[:venue_name] %>
    </p>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">Your booking still stands. You can cancel or rebook free of charge from your account.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Manage booking", assigns[:manage_url]) %>
    """,
    text: """
    Session rescheduled

    <%= assigns[:offering_name] %> has a new time.

    From: <%= assigns[:from_starts_at] %>
    To: <%= assigns[:to_starts_at] %><%= if assigns[:venue_name], do: " at " <> assigns[:venue_name] %>

    Your booking still stands. You can cancel or rebook free of charge from your account.

    Manage booking: <%= assigns[:manage_url] %>
    """,
    sample: %{
      offering_name: "U12 Skills",
      from_starts_at: "Tue, 6 Jan 2026 at 5:00 PM",
      to_starts_at: "Thu, 8 Jan 2026 at 5:00 PM",
      venue_name: "Riverside Field",
      manage_url: "https://localhost/portal/bookings"
    }
end
