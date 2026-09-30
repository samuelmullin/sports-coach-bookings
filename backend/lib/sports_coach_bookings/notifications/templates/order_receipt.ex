defmodule SportsCoachBookings.Notifications.Templates.OrderReceipt do
  @moduledoc "Order receipt with lines, discounts, tax, and total. `:order_receipt`."

  use SportsCoachBookings.Notifications.Template,
    required: [:order_number, :total],
    subject: "Receipt for order <%= assigns[:order_number] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Thanks for your purchase</h1>
    <p style="margin:0 0 16px 0;">Order <strong><%= assigns[:order_number] %></strong> is paid.</p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px 0;font-size:15px;border-collapse:collapse;">
      <tr>
        <th align="left" style="padding:6px 0;border-bottom:1px solid #e5e7eb;">Item</th>
        <th align="right" style="padding:6px 0;border-bottom:1px solid #e5e7eb;">Total</th>
      </tr>
      <%= for line <- assigns[:lines] || [] do %>
        <tr>
          <td colspan="2" style="padding:6px 0;"><%= line %></td>
        </tr>
      <% end %>
      <%= if assigns[:discount_total] do %><tr><td style="padding:6px 0;color:#6b7280;">Discount</td><td align="right" style="padding:6px 0;">-<%= assigns[:discount_total] %></td></tr><% end %>
      <%= if assigns[:tax_total] do %><tr><td style="padding:6px 0;color:#6b7280;">Tax<%= if assigns[:tax_number], do: " (" <> assigns[:tax_number] <> ")" %></td><td align="right" style="padding:6px 0;"><%= assigns[:tax_total] %></td></tr><% end %>
      <tr><td style="padding:6px 0;font-weight:bold;border-top:1px solid #e5e7eb;">Total</td><td align="right" style="padding:6px 0;font-weight:bold;border-top:1px solid #e5e7eb;"><%= assigns[:total] %></td></tr>
    </table>
    <%= if assigns[:pickup_note] do %><p style="margin:0 0 16px 0;"><strong>Pickup:</strong> <%= assigns[:pickup_note] %></p><% end %>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("View order", assigns[:order_url]) %>
    """,
    text: """
    Thanks for your purchase

    Order <%= assigns[:order_number] %> is paid.
    <%= for line <- assigns[:lines] || [] do %>
    <%= line %><% end %>
    <%= if assigns[:discount_total], do: "Discount: -" <> assigns[:discount_total] <> "\n" %><%= if assigns[:tax_total], do: "Tax: " <> assigns[:tax_total] <> "\n" %><%= if assigns[:pickup_note], do: "Pickup: " <> assigns[:pickup_note] <> "\n" %>
    Total: <%= assigns[:total] %>

    View order: <%= assigns[:order_url] %>
    """,
    sample: %{
      order_number: "A-000123",
      total: "$115.00 CAD",
      lines: ["U12 Package x1 - $100.00 CAD"],
      discount_total: "$10.00 CAD",
      tax_total: "$25.00 CAD",
      tax_number: "GST-123",
      pickup_note: nil,
      order_url: "https://localhost/portal/orders/sample"
    }
end
