defmodule SportsCoachBookings.Notifications.Templates.OrderRefunded do
  @moduledoc "Order refund confirmation. `:order_refunded`."

  use SportsCoachBookings.Notifications.Template,
    required: [:order_number, :refunded_total],
    subject: "Refund for order <%= assigns[:order_number] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Refund issued</h1>
    <p style="margin:0 0 16px 0;">A refund of <strong><%= assigns[:refunded_total] %></strong> has been issued for order <strong><%= assigns[:order_number] %></strong>.</p>
    <%= if assigns[:reason] do %><p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">Reason: <%= assigns[:reason] %></p><% end %>
    <p style="margin:0 0 16px 0;color:#6b7280;font-size:14px;">Depending on your bank, it may take several business days to appear.</p>
    """,
    text: """
    Refund issued

    A refund of <%= assigns[:refunded_total] %> has been issued for order <%= assigns[:order_number] %>.
    <%= if assigns[:reason], do: "Reason: " <> assigns[:reason] <> "\n" %>
    Depending on your bank, it may take several business days to appear.
    """,
    sample: %{
      order_number: "A-000123",
      refunded_total: "$25.00 CAD",
      reason: "requested_by_customer"
    }
end
