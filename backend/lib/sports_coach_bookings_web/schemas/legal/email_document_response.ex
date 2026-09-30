defmodule SportsCoachBookingsWeb.Schemas.Legal.EmailDocumentResponse do
  @moduledoc "Acknowledgement that a document copy was queued."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EmailDocumentResponse",
    type: :object,
    properties: %{
      status: %Schema{type: :string, enum: ["queued"]},
      email: %Schema{type: :string, format: :email}
    },
    required: [:status, :email]
  })
end
