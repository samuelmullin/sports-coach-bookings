defmodule SportsCoachBookings.Notifications.Templates.WaiverSigned do
  @moduledoc "Confirmation that a waiver was signed. `:waiver_signed`."

  use SportsCoachBookings.Notifications.Template,
    required: [:waiver_name],
    subject: "<%= assigns[:waiver_name] %> signed",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Waiver signed</h1>
    <p style="margin:0 0 16px 0;">Thank you<%= if assigns[:player_name], do: ", " <> assigns[:player_name] %>. The <strong><%= assigns[:waiver_name] %></strong> has been signed and recorded.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View waivers", assigns[:waivers_url]) %>
    """,
    text: """
    Waiver signed

    Thank you<%= if assigns[:player_name], do: ", " <> assigns[:player_name] %>. The <%= assigns[:waiver_name] %> has been signed and recorded.

    View waivers: <%= assigns[:waivers_url] %>
    """,
    sample: %{
      waiver_name: "Participation Waiver",
      player_name: "Riley",
      waivers_url: "https://localhost/portal/waivers"
    }
end
