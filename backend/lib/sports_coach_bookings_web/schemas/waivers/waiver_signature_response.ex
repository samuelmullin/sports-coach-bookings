defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverSignatureResponse do
  @moduledoc "A waiver signature."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WaiverSignatureResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      waiver_version_id: %Schema{type: :string, format: :uuid},
      player_id: %Schema{type: :string, format: :uuid},
      customer_user_id: %Schema{type: :string, format: :uuid},
      signer_name_typed: %Schema{type: :string},
      signer_relationship: %Schema{type: :string, nullable: true},
      consent_checkbox: %Schema{type: :boolean},
      signed_at: %Schema{type: :string, format: :"date-time"},
      ip: %Schema{type: :string, nullable: true},
      user_agent: %Schema{type: :string, nullable: true},
      content_sha256: %Schema{type: :string},
      pdf_key: %Schema{type: :string, nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :waiver_version_id, :player_id, :signer_name_typed, :consent_checkbox]
  })
end
