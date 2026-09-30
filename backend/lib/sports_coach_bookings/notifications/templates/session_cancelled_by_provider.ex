defmodule SportsCoachBookings.Notifications.Templates.SessionCancelledByProvider do
  @moduledoc "Session cancelled by the provider. `:session_cancelled_by_provider`."

  use SportsCoachBookings.Notifications.Template,
    required: [:offering_name, :starts_at],
    subject: "Session cancelled: <%= assigns[:offering_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Session cancelled</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:offering_name] %></strong> on <%= assigns[:starts_at] %> has been cancelled by the provider.</p>
    <%= if assigns[:reason] do %><p style="margin:0 0 16px 0;"><strong>Reason:</strong> <%= assigns[:reason] %></p><% end %>
    <p style="margin:0 0 16px 0;">Credits or payments for affected bookings are returned automatically.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View your bookings", assigns[:manage_url]) %>
    """,
    text: """
    Session cancelled

    <%= assigns[:offering_name] %> on <%= assigns[:starts_at] %> has been cancelled by the provider.
    <%= if assigns[:reason], do: "Reason: " <> assigns[:reason] <> "\n" %>
    Credits or payments for affected bookings are returned automatically.

    View your bookings: <%= assigns[:manage_url] %>
    """,
    sample: %{
      offering_name: "U12 Skills",
      starts_at: "Tue, 6 Jan 2026 at 5:00 PM",
      reason: "Field unavailable",
      manage_url: "https://localhost/portal/bookings"
    }
end
