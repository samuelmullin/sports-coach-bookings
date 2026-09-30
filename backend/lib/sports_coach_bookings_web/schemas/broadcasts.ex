defmodule SportsCoachBookingsWeb.Schemas.Broadcasts do
  @moduledoc "OpenApiSpex schemas for WP-17 staff broadcast endpoints."

  alias OpenApiSpex.Schema

  def broadcast do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        subject: %Schema{type: :string},
        body_markdown: %Schema{type: :string},
        category: %Schema{type: :string, enum: ["operational", "marketing"]},
        segment: %Schema{type: :object, additionalProperties: true},
        status: %Schema{
          type: :string,
          enum: ["draft", "scheduled", "sending", "sent", "cancelled"]
        },
        scheduled_for: %Schema{type: :string, nullable: true},
        sent_at: %Schema{type: :string, nullable: true},
        created_by: %Schema{type: :string, format: :uuid, nullable: true},
        recipient_count: %Schema{type: :integer},
        stats: %Schema{type: :object, additionalProperties: true},
        inserted_at: %Schema{type: :string, nullable: true},
        updated_at: %Schema{type: :string, nullable: true}
      },
      required: [:id, :subject, :body_markdown, :category, :status]
    }
  end

  def broadcast_list do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: broadcast()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end

  def create_request do
    %Schema{
      type: :object,
      properties: %{
        subject: %Schema{type: :string},
        body_markdown: %Schema{type: :string},
        category: %Schema{type: :string, enum: ["operational", "marketing"]},
        segment: %Schema{type: :object, additionalProperties: true}
      },
      required: [:subject, :body_markdown, :category]
    }
  end

  def update_request do
    %Schema{
      type: :object,
      properties: %{
        subject: %Schema{type: :string},
        body_markdown: %Schema{type: :string},
        category: %Schema{type: :string, enum: ["operational", "marketing"]},
        segment: %Schema{type: :object, additionalProperties: true}
      }
    }
  end

  def preview_response do
    %Schema{
      type: :object,
      properties: %{
        subject: %Schema{type: :string},
        html: %Schema{type: :string},
        text: %Schema{type: :string},
        recipient_count: %Schema{type: :integer},
        recipients: %Schema{type: :array, items: %Schema{type: :string, format: :email}}
      },
      required: [:subject, :html, :recipient_count]
    }
  end

  def recipient_count_response do
    %Schema{
      type: :object,
      properties: %{
        recipient_count: %Schema{type: :integer},
        marketing_filtered: %Schema{type: :boolean},
        recipients: %Schema{type: :array, items: %Schema{type: :string, format: :email}}
      },
      required: [:recipient_count]
    }
  end

  def test_request do
    %Schema{
      type: :object,
      properties: %{email: %Schema{type: :string, format: :email, nullable: true}}
    }
  end

  def test_response do
    %Schema{
      type: :object,
      properties: %{
        message_id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        status: %Schema{type: :string}
      },
      required: [:message_id, :email]
    }
  end

  def schedule_request do
    %Schema{
      type: :object,
      properties: %{scheduled_for: %Schema{type: :string, format: :"date-time"}},
      required: [:scheduled_for]
    }
  end

  def recipient do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        recipient_type: %Schema{type: :string, enum: ["customer_user", "staff_user", "email"]},
        status: %Schema{type: :string, enum: ["pending", "sent", "suppressed", "failed"]},
        delivery_status: %Schema{type: :string, nullable: true},
        message_id: %Schema{type: :string, format: :uuid, nullable: true},
        delivery_id: %Schema{type: :string, format: :uuid, nullable: true},
        sent_at: %Schema{type: :string, nullable: true},
        error: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, nullable: true}
      },
      required: [:id, :email, :status]
    }
  end

  def history_response do
    %Schema{
      type: :object,
      properties: %{
        broadcast: broadcast(),
        stats: %Schema{type: :object, additionalProperties: true},
        data: %Schema{type: :array, items: recipient()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:broadcast, :stats, :data]
    }
  end
end
