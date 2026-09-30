defmodule SportsCoachBookings.Notifications.Templates.CreditsExpiring do
  @moduledoc "Reminder that credits expire soon. `:credits_expiring`."

  use SportsCoachBookings.Notifications.Template,
    required: [:amount, :expires_at],
    subject: "<%= assigns[:amount] %> credit(s) expiring soon",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Your credits expire soon</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:amount] %></strong> credit(s) expire on <strong><%= assigns[:expires_at] %></strong>.</p>
    <p style="margin:0 0 16px 0;">Book a session before then so you don't lose them.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Book now", assigns[:book_url]) %>
    """,
    text: """
    Your credits expire soon

    <%= assigns[:amount] %> credit(s) expire on <%= assigns[:expires_at] %>.

    Book a session before then so you don't lose them.

    Book now: <%= assigns[:book_url] %>
    """,
    sample: %{amount: "3", expires_at: "1 Mar 2026", book_url: "https://localhost/portal"}
end
