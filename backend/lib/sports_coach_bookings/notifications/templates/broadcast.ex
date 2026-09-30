defmodule SportsCoachBookings.Notifications.Templates.Broadcast do
  @moduledoc """
  Staff broadcast email. The subject, HTML, and text are supplied as assigns
  (the Markdown body is rendered to a safe HTML fragment by
  `SportsCoachBookings.Notifications.Broadcasts.Markdown`). Registered under
  `:broadcast` by WP-17.
  """

  use SportsCoachBookings.Notifications.Template,
    required: [:subject, :body_html, :body_text],
    subject: "<%= assigns[:subject] %>",
    html: """
    <%= assigns[:body_html] %>
    """,
    text: """
    <%= assigns[:body_text] %>
    """,
    sample: %{
      subject: "Fall programs are open",
      body_html: "<h1>Fall programs are open</h1><p>Registration is now live.</p>",
      body_text: "Fall programs are open\n\nRegistration is now live."
    }
end
