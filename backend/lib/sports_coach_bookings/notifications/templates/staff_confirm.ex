defmodule SportsCoachBookings.Notifications.Templates.StaffConfirm do
  @moduledoc "Staff email-confirmation template. Registered as `:staff_confirm`."

  use SportsCoachBookings.Notifications.Template,
    required: [:email, :token],
    subject: "Confirm your email address",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Confirm your email</h1>
    <p style="margin:0 0 16px 0;">Please confirm your email address to activate your staff account.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Confirm email", SportsCoachBookings.Notifications.Templates.Helpers.link("/confirm", assigns[:token])) %>
    """,
    text: """
    Confirm your email

    <%= SportsCoachBookings.Notifications.Templates.Helpers.link("/confirm", assigns[:token]) %>
    """
end
