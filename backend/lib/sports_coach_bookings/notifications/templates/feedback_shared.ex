defmodule SportsCoachBookings.Notifications.Templates.FeedbackShared do
  @moduledoc "Coach feedback shared with a household. `:feedback_shared`."

  use SportsCoachBookings.Notifications.Template,
    required: [:player_name, :body],
    subject:
      "New feedback for <%= assigns[:player_name] %><%= if assigns[:updated], do: \" (updated)\" %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Coach feedback<%= if assigns[:updated], do: " (updated)" %></h1>
    <p style="margin:0 0 8px 0;color:#6b7280;font-size:14px;"><%= assigns[:coach_name] %><%= if assigns[:session_date], do: " - " <> assigns[:session_date] %></p>
    <p style="margin:0 0 16px 0;"><%= assigns[:body] %></p>
    <%= if assigns[:ratings] && assigns[:ratings] != [] do %>
      <ul style="margin:0 0 16px 0;padding-left:18px;font-size:14px;">
        <%= for rating <- assigns[:ratings] do %>
          <li><%= rating %></li>
        <% end %>
      </ul>
    <% end %>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View feedback", assigns[:feedback_url]) %>
    """,
    text: """
    Coach feedback<%= if assigns[:updated], do: " (updated)" %>

    <%= assigns[:coach_name] %><%= if assigns[:session_date], do: " - " <> assigns[:session_date] %>
    <%= assigns[:body] %>
    <%= for rating <- assigns[:ratings] || [] do %>
    <%= rating %><% end %>

    View feedback: <%= assigns[:feedback_url] %>
    """,
    sample: %{
      player_name: "Riley",
      coach_name: "Coach Sam",
      session_date: "6 Jan 2026",
      body: "Strong session; keep working on the first touch.",
      ratings: ["First touch: 4/5"],
      updated: false,
      feedback_url: "https://localhost/portal/feedback"
    }
end
