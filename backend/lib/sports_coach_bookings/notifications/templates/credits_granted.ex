defmodule SportsCoachBookings.Notifications.Templates.CreditsGranted do
  @moduledoc "Credits added to a household. `:credits_granted`."

  use SportsCoachBookings.Notifications.Template,
    required: [:amount],
    subject: "You have <%= assigns[:amount] %> new credit(s)",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Credits added</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:amount] %></strong> credit(s) have been added to your household<%= if assigns[:balance], do: " (new balance: " <> assigns[:balance] <> ")" %>.</p>
    <%= if assigns[:expires_at] do %><p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">They expire on <%= assigns[:expires_at] %>.</p><% end %>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Book a session", assigns[:book_url]) %>
    """,
    text: """
    Credits added

    <%= assigns[:amount] %> credit(s) have been added to your household<%= if assigns[:balance], do: " (new balance: " <> assigns[:balance] <> ")" %>.
    <%= if assigns[:expires_at], do: "They expire on " <> assigns[:expires_at] <> ".\n" %>

    Book a session: <%= assigns[:book_url] %>
    """,
    sample: %{
      amount: "5",
      balance: "8",
      expires_at: "1 Mar 2026",
      book_url: "https://localhost/portal"
    }
end
