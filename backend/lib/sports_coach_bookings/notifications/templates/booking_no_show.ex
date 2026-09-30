defmodule SportsCoachBookings.Notifications.Templates.BookingNoShow do
  @moduledoc "No-show notice and its outcome. `:booking_no_show`."

  use SportsCoachBookings.Notifications.Template,
    required: [:player_name, :offering_name],
    subject: "Marked as no-show: <%= assigns[:player_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Marked as no-show</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:player_name] %></strong> was marked absent for <strong><%= assigns[:offering_name] %></strong>.</p>
    <%= if assigns[:outcome] do %><p style="margin:0 0 16px 0;"><strong>Outcome:</strong> <%= assigns[:outcome] %></p><% end %>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">If this is a mistake, contact your coaching provider.</p>
    """,
    text: """
    Marked as no-show

    <%= assigns[:player_name] %> was marked absent for <%= assigns[:offering_name] %>.
    <%= if assigns[:outcome], do: "Outcome: " <> assigns[:outcome] <> "\n" %>

    If this is a mistake, contact your coaching provider.
    """,
    sample: %{
      player_name: "Riley",
      offering_name: "U12 Skills",
      outcome: "Booking forfeited"
    }
end
