defmodule SportsCoachBookings.Notifications.Templates.CustomerEmailChange do
  @moduledoc "Customer email-change confirmation template. Registered as `:customer_email_change`."

  use SportsCoachBookings.Notifications.Template,
    required: [:email, :previous_email, :token],
    subject: "Confirm your new email address",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Confirm your new email</h1>
    <p style="margin:0 0 16px 0;">You changed the email on your account from <strong><%= assigns[:previous_email] %></strong> to <strong><%= assigns[:email] %></strong>.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Confirm new email", SportsCoachBookings.Notifications.Templates.Helpers.link("/confirm-email", assigns[:token])) %>
    """,
    text: """
    Confirm your new email

    You changed the email on your account from <%= assigns[:previous_email] %> to <%= assigns[:email] %>.

    <%= SportsCoachBookings.Notifications.Templates.Helpers.link("/confirm-email", assigns[:token]) %>
    """
end
