defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverPdfResponse do
  @moduledoc "Metadata for a signature's PDF snapshot (S3 is not configured)."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WaiverPdfResponse",
    type: :object,
    properties: %{
      signature_id: %Schema{type: :string, format: :uuid},
      pdf_key: %Schema{type: :string, nullable: true},
      status: %Schema{type: :string, enum: ["pending", "ready"]},
      download_url: %Schema{type: :string, nullable: true}
    },
    required: [:signature_id, :status]
  })
end
