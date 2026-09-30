defmodule SportsCoachBookings.Notifications.Templates.BookingCancelled do
  @moduledoc "Booking cancellation with its outcome. `:booking_cancelled`."

  use SportsCoachBookings.Notifications.Template,
    required: [:player_name, :offering_name, :outcome],
    subject: "Booking cancelled: <%= assigns[:offering_name] %> for <%= assigns[:player_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Booking cancelled</h1>
    <p style="margin:0 0 16px 0;">The booking for <strong><%= assigns[:player_name] %></strong> in <strong><%= assigns[:offering_name] %></strong> has been cancelled.</p>
    <p style="margin:0 0 16px 0;"><strong>Outcome:</strong> <%= assigns[:outcome] %></p>
    <%= if assigns[:starts_at] do %><p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">Was scheduled for <%= assigns[:starts_at] %>.</p><% end %>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Book another session", assigns[:manage_url]) %>
    """,
    text: """
    Booking cancelled

    The booking for <%= assigns[:player_name] %> in <%= assigns[:offering_name] %> has been cancelled.

    Outcome: <%= assigns[:outcome] %>
    <%= if assigns[:starts_at], do: "Was scheduled for " <> assigns[:starts_at] <> "\n" %>

    Book another session: <%= assigns[:manage_url] %>
    """,
    sample: %{
      player_name: "Riley",
      offering_name: "U12 Skills",
      outcome: "1 credit returned",
      starts_at: "Tue, 6 Jan 2026 at 5:00 PM",
      manage_url: "https://localhost/portal"
    }
end
