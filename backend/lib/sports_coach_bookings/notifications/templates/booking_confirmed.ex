defmodule SportsCoachBookings.Notifications.Templates.BookingConfirmed do
  @moduledoc "Booking confirmation with session, venue, coach, and calendar. `:booking_confirmed`."

  use SportsCoachBookings.Notifications.Template,
    required: [:player_name, :offering_name, :starts_at],
    subject: "Booking confirmed: <%= assigns[:offering_name] %> for <%= assigns[:player_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Booking confirmed</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:player_name] %></strong> is booked into <strong><%= assigns[:offering_name] %></strong>.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 16px 0;font-size:15px;">
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">When</td><td style="padding:4px 0;"><%= assigns[:starts_at] %></td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Venue</td><td style="padding:4px 0;"><%= assigns[:venue_name] %></td></tr>
      <%= if assigns[:coach_name] do %><tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Coach</td><td style="padding:4px 0;"><%= assigns[:coach_name] %></td></tr><% end %>
      <%= if assigns[:booking_reference] do %><tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Reference</td><td style="padding:4px 0;"><%= assigns[:booking_reference] %></td></tr><% end %>
    </table>
    <%= if assigns[:venue_address] do %><p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;"><%= assigns[:venue_address] %><%= if assigns[:map_url], do: " - " <> assigns[:map_url] %></p><% end %>
    <%= if assigns[:policy_summary] do %><p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;"><strong>Cancellation policy:</strong> <%= assigns[:policy_summary] %></p><% end %>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Manage booking", assigns[:manage_url]) %>
    <p style="margin:0;color:#6b7280;font-size:14px;">A calendar invitation is attached.</p>
    """,
    text: """
    Booking confirmed

    <%= assigns[:player_name] %> is booked into <%= assigns[:offering_name] %>.

    When: <%= assigns[:starts_at] %>
    Venue: <%= assigns[:venue_name] %>
    <%= if assigns[:coach_name], do: "Coach: " <> assigns[:coach_name] <> "\n" %><%= if assigns[:booking_reference], do: "Reference: " <> assigns[:booking_reference] <> "\n" %><%= if assigns[:policy_summary], do: "Cancellation policy: " <> assigns[:policy_summary] <> "\n" %>

    Manage booking: <%= assigns[:manage_url] %>

    A calendar invitation is attached.
    """,
    sample: %{
      player_name: "Riley",
      offering_name: "U12 Skills",
      starts_at: "Tue, 6 Jan 2026 at 5:00 PM",
      venue_name: "Riverside Field",
      coach_name: "Coach Sam",
      booking_reference: "A-000123",
      venue_address: "1 Riverside Way, Toronto",
      map_url: "https://maps.example.com/riverside",
      policy_summary: "Full credit if cancelled 24h before",
      manage_url: "https://localhost/portal/bookings/sample"
    }
end
