defmodule SportsCoachBookingsWeb.Schemas.Waivers.SignWaiverRequest do
  @moduledoc "Payload for signing a waiver version."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SignWaiverRequest",
    type: :object,
    properties: %{
      content_sha256: %Schema{type: :string},
      signer_name_typed: %Schema{type: :string},
      signer_relationship: %Schema{type: :string, nullable: true},
      consent_checkbox: %Schema{type: :boolean}
    },
    required: [:content_sha256, :signer_name_typed, :consent_checkbox]
  })
end
