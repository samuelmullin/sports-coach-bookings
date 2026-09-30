defmodule SportsCoachBookings.Notifications.Templates.CustomerWelcome do
  @moduledoc "Welcome email for a newly registered customer. `:customer_welcome`."

  use SportsCoachBookings.Notifications.Template,
    required: [:first_name],
    subject: "Welcome to the team, <%= assigns[:first_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Welcome, <%= assigns[:first_name] %></h1>
    <p style="margin:0 0 16px 0;">Your account is ready. From your household you can add players, sign required waivers, buy packages, and book sessions.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Go to your account", assigns[:account_url]) %>
    """,
    text: """
    Welcome, <%= assigns[:first_name] %>

    Your account is ready. From your household you can add players, sign required waivers, buy packages, and book sessions.

    Go to your account: <%= assigns[:account_url] %>
    """,
    sample: %{first_name: "Casey", account_url: "https://localhost/portal"}
end
