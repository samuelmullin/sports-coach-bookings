defmodule SportsCoachBookings.Notifications.Templates.Sample do
  @moduledoc "A sample template used by tests and the `/dev/emails` preview."

  use SportsCoachBookings.Notifications.Template,
    required: [:name, :action_url],
    subject: "Welcome, <%= assigns[:name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Hi <%= assigns[:name] %></h1>
    <p style="margin:0 0 16px 0;">This is a sample notification from SportsCoachBookings.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Open your account", assigns[:action_url]) %>
    <p style="margin:0;color:#6b7280;font-size:14px;">If you did not expect this email, you can ignore it.</p>
    """,
    text: """
    Hi <%= assigns[:name] %>,

    This is a sample notification from SportsCoachBookings.

    Open your account: <%= assigns[:action_url] %>

    If you did not expect this email, you can ignore it.
    """,
    sample: %{name: "Alex", action_url: "https://localhost/portal"}
end
