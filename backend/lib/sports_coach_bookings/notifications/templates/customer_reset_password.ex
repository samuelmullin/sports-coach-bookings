defmodule SportsCoachBookings.Notifications.Templates.CustomerResetPassword do
  @moduledoc """
  Customer password-reset template. Registered as `:customer_reset_password`.

  Password reset is exempt from suppression (a user with a bounced mailbox must
  still be able to regain access).
  """

  use SportsCoachBookings.Notifications.Template,
    required: [:email, :token],
    exempt: true,
    subject: "Reset your password",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Reset your password</h1>
    <p style="margin:0 0 16px 0;">We received a request to reset your password. Choose a new one using the link below.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Choose a new password", SportsCoachBookings.Notifications.Templates.Helpers.portal_link("/reset-password", assigns[:token])) %>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">If you did not request this, you can ignore this email.</p>
    """,
    text: """
    Reset your password

    <%= SportsCoachBookings.Notifications.Templates.Helpers.portal_link("/reset-password", assigns[:token]) %>

    If you did not request this, you can ignore this email.
    """
end
