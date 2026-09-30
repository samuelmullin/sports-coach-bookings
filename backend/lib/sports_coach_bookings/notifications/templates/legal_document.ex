defmodule SportsCoachBookings.Notifications.Templates.LegalDocument do
  @moduledoc """
  Emails a copy of a legal document or waiver body. `:legal_document`.

  `:body` is the plain-text rendering and `:body_html` the HTML rendering of the
  same markdown, so the text alternative and the HTML part agree.
  """

  use SportsCoachBookings.Notifications.Template,
    required: [:title, :body, :body_html],
    subject: "<%= assigns[:title] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;"><%= assigns[:title] %></h1>
    <div style="margin:0;font-size:15px;line-height:1.6;"><%= assigns[:body_html] %></div>
    <hr style="border:none;border-top:1px solid #e5e7eb;margin:24px 0;" />
    <p style="margin:0;font-size:13px;color:#6b7280;">You requested a copy of this document from SportsCoachBookings.</p>
    """,
    text: """
    <%= assigns[:title] %>

    <%= assigns[:body] %>

    --
    You requested a copy of this document from SportsCoachBookings.
    """,
    sample: %{
      title: "Terms of Service",
      body: "Welcome to SportsCoachBookings.\n\nBy creating an account you agree to these terms.",
      body_html: "<p>Welcome to SportsCoachBookings.</p>"
    }
end
