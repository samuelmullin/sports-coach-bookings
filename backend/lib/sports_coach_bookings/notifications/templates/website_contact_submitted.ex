defmodule SportsCoachBookings.Notifications.Templates.WebsiteContactSubmitted do
  @moduledoc "Operator notification for a hosted-site contact inquiry."

  use SportsCoachBookings.Notifications.Template,
    required: [:name, :email, :phone, :subject, :message],
    subject: "New website inquiry: <%= assigns[:subject] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">New website inquiry</h1>
    <p><strong>From:</strong> <%= SportsCoachBookings.Notifications.Templates.Helpers.escape_html(assigns[:name]) %> &lt;<%= SportsCoachBookings.Notifications.Templates.Helpers.escape_html(assigns[:email]) %>&gt;</p>
    <p><strong>Phone:</strong> <%= SportsCoachBookings.Notifications.Templates.Helpers.escape_html(assigns[:phone]) %></p>
    <p><strong>Subject:</strong> <%= SportsCoachBookings.Notifications.Templates.Helpers.escape_html(assigns[:subject]) %></p>
    <p style="white-space:pre-wrap;"><%= SportsCoachBookings.Notifications.Templates.Helpers.escape_html(assigns[:message]) %></p>
    """,
    text: """
    New website inquiry

    From: <%= assigns[:name] %> <<%= assigns[:email] %>>
    Phone: <%= assigns[:phone] %>
    Subject: <%= assigns[:subject] %>

    <%= assigns[:message] %>
    """
end
