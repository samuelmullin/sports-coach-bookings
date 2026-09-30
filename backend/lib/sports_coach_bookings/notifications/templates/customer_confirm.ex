defmodule SportsCoachBookings.Notifications.Templates.CustomerConfirm do
  @moduledoc "Customer account email-confirmation template. Registered as `:customer_confirm`."

  use SportsCoachBookings.Notifications.Template,
    required: [:email, :token],
    subject: "Confirm your email address",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Confirm your email</h1>
    <p style="margin:0 0 16px 0;">Please confirm your email address to finish setting up your account.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Confirm email", SportsCoachBookings.Notifications.Templates.Helpers.link("/confirm", assigns[:token])) %>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">This link expires in 7 days.</p>
    """,
    text: """
    Confirm your email address

    <%= SportsCoachBookings.Notifications.Templates.Helpers.link("/confirm", assigns[:token]) %>

    This link expires in 7 days.
    """
end
