defmodule SportsCoachBookings.Notifications.Templates.WaiverResignRequired do
  @moduledoc "A new waiver version requires re-signing. `:waiver_resign_required`."

  use SportsCoachBookings.Notifications.Template,
    required: [:waiver_name],
    subject: "Please sign the updated <%= assigns[:waiver_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">An updated waiver needs your signature</h1>
    <p style="margin:0 0 16px 0;">The <strong><%= assigns[:waiver_name] %></strong> has been updated and needs to be signed again<%= if assigns[:player_name], do: " for " <> assigns[:player_name] %> before the next booking.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Sign now", assigns[:sign_url]) %>
    """,
    text: """
    An updated waiver needs your signature

    The <%= assigns[:waiver_name] %> has been updated and needs to be signed again<%= if assigns[:player_name], do: " for " <> assigns[:player_name] %> before the next booking.

    Sign now: <%= assigns[:sign_url] %>
    """,
    sample: %{
      waiver_name: "Participation Waiver",
      player_name: "Riley",
      sign_url: "https://localhost/portal/waivers"
    }
end
