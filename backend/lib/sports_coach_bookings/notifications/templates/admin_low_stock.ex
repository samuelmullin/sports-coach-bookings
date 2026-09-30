defmodule SportsCoachBookings.Notifications.Templates.AdminLowStock do
  @moduledoc "Admin alert that a product variant is low on stock. `:admin_low_stock`."

  use SportsCoachBookings.Notifications.Template,
    required: [:product_name, :available, :threshold],
    subject: "Low stock: <%= assigns[:product_name] %>",
    html: """
    <h1 style="margin:0 0 16px 0;font-size:24px;">Low stock alert</h1>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:product_name] %></strong><%= if assigns[:variant_label], do: " (" <> assigns[:variant_label] <> ")" %> is low.</p>
    <p style="margin:0 0 16px 0;"><strong><%= assigns[:available] %></strong> remaining, threshold <strong><%= assigns[:threshold] %></strong>.</p>
    <%= SportsCoachBookings.Notifications.Templates.Helpers.button("Manage inventory", assigns[:inventory_url]) %>
    """,
    text: """
    Low stock alert

    <%= assigns[:product_name] %><%= if assigns[:variant_label], do: " (" <> assigns[:variant_label] <> ")" %> is low.

    <%= assigns[:available] %> remaining, threshold <%= assigns[:threshold] %>.

    Manage inventory: <%= assigns[:inventory_url] %>
    """,
    sample: %{
      product_name: "Training Jersey",
      variant_label: "size YM",
      available: 1,
      threshold: 2,
      inventory_url: "https://localhost/admin/inventory"
    }
end
