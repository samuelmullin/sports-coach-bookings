defmodule SportsCoachBookingsWeb.Schemas.Websites do
  @moduledoc false

  alias OpenApiSpex.Schema

  def site do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, nullable: true},
        enabled: %Schema{type: :boolean},
        draft_content: content(),
        preview_content: content(),
        published_content: content(),
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:enabled, :draft_content, :preview_content, :published_content]
    }
  end

  def site_update do
    %Schema{
      type: :object,
      properties: %{enabled: %Schema{type: :boolean}, content: content()},
      required: [:content]
    }
  end

  def published_site do
    %Schema{
      type: :object,
      properties: %{
        enabled: %Schema{type: :boolean},
        published_at: %Schema{type: :string, format: :"date-time"},
        content: content()
      },
      required: [:enabled, :published_at, :content]
    }
  end

  def contact_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, maxLength: 120},
        email: %Schema{type: :string, format: :email, maxLength: 320},
        phone: %Schema{type: :string, nullable: true, maxLength: 40},
        company: %Schema{type: :string, nullable: true, maxLength: 160},
        subject: %Schema{type: :string, nullable: true, maxLength: 160},
        message: %Schema{type: :string, minLength: 10, maxLength: 5_000}
      },
      required: [:name, :email, :message]
    }
  end

  def contact_submission do
    %Schema{
      type: :object,
      properties:
        Map.merge(contact_request().properties, %{
          id: %Schema{type: :string, format: :uuid},
          status: %Schema{type: :string, enum: ["new", "read", "resolved"]},
          resolved_at: %Schema{type: :string, format: :"date-time", nullable: true},
          inserted_at: %Schema{type: :string, format: :"date-time"}
        }),
      required: [:id, :name, :email, :message, :status, :inserted_at]
    }
  end

  def contact_list do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: contact_submission()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end

  def contact_update do
    %Schema{
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["new", "read", "resolved"]}},
      required: [:status]
    }
  end

  defp content, do: %Schema{type: :object, additionalProperties: true}
end
