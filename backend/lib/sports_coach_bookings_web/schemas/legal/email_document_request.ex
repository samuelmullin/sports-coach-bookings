defmodule SportsCoachBookingsWeb.Schemas.Legal.EmailDocumentRequest do
  @moduledoc "Request to email a copy of a document to an address."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EmailDocumentRequest",
    type: :object,
    properties: %{
      email: %Schema{type: :string, format: :email}
    },
    required: [:email]
  })
end
