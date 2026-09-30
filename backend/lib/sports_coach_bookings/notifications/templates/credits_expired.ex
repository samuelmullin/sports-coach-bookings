defmodule SportsCoachBookings.Notifications.Templates.CreditsExpired do
  @moduledoc "Notice that credits expired. `:credits_expired`."

  use SportsCoachBookings.Notifications.Template,
    required: [:amount],
    subject: "<%= assigns[:amount] %> credit(s) expired",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Credits expired</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:amount] %></strong> unused credit(s) have expired.</p>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">You can still buy a new package at any time.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Browse packages", assigns[:book_url]) %>
    """,
    text: """
    Credits expired

    <%= assigns[:amount] %> unused credit(s) have expired.

    You can still buy a new package at any time.

    Browse packages: <%= assigns[:book_url] %>
    """,
    sample: %{amount: "2", book_url: "https://localhost/portal"}
end
