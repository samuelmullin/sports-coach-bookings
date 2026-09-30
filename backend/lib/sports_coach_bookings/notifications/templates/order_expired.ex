defmodule SportsCoachBookings.Notifications.Templates.OrderExpired do
  @moduledoc "Unpaid order expired and holds released. `:order_expired`."

  use SportsCoachBookings.Notifications.Template,
    required: [:order_number],
    subject: "Order <%= assigns[:order_number] %> expired",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Order expired</h1>
    <p style="margin:0 0 16px 0;">Order <strong><%= assigns[:order_number] %></strong> was not paid in time, so any held seats have been released.</p>
    <p style="margin:0 0 16px 0;">You can start a new booking at any time.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Browse sessions", assigns[:book_url]) %>
    """,
    text: """
    Order expired

    Order <%= assigns[:order_number] %> was not paid in time, so any held seats have been released.

    You can start a new booking at any time.

    Browse sessions: <%= assigns[:book_url] %>
    """,
    sample: %{order_number: "A-000123", book_url: "https://localhost/portal"}
end
