defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverVersionResponse do
  @moduledoc "A waiver version."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WaiverVersionResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      waiver_template_id: %Schema{type: :string, format: :uuid},
      version: %Schema{type: :integer},
      body_markdown: %Schema{type: :string},
      status: %Schema{type: :string, enum: ["draft", "published", "superseded"]},
      published_at: %Schema{type: :string, format: :"date-time", nullable: true},
      content_sha256: %Schema{type: :string},
      immutable: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :waiver_template_id, :version, :body_markdown, :status, :content_sha256]
  })
end
