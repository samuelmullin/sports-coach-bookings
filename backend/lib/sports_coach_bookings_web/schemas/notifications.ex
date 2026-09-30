defmodule SportsCoachBookingsWeb.Schemas.Notifications do
  @moduledoc "OpenApiSpex schemas for WP-05 notification administration endpoints."

  alias OpenApiSpex.Schema

  def delivery do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        message_id: %Schema{type: :string, format: :uuid},
        template_key: %Schema{type: :string, nullable: true},
        category: %Schema{type: :string, nullable: true},
        subject: %Schema{type: :string, nullable: true},
        recipient_type: %Schema{type: :string, enum: ["customer_user", "staff_user", "email"]},
        recipient_id: %Schema{type: :string, format: :uuid, nullable: true},
        email: %Schema{type: :string, format: :email},
        status: %Schema{
          type: :string,
          enum: ["queued", "sent", "delivered", "bounced", "complained", "failed", "suppressed"]
        },
        provider_ref: %Schema{type: :string, nullable: true},
        sent_at: %Schema{type: :string, nullable: true},
        delivered_at: %Schema{type: :string, nullable: true},
        bounced_at: %Schema{type: :string, nullable: true},
        error: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, nullable: true}
      },
      required: [:id, :message_id, :email, :status]
    }
  end

  def delivery_list do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: delivery()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end
end
