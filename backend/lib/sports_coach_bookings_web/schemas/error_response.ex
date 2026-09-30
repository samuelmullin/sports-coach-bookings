defmodule SportsCoachBookingsWeb.Schemas.ErrorResponse do
  @moduledoc "The standard error envelope."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ErrorResponse",
    type: :object,
    properties: %{
      error: %Schema{
        type: :object,
        properties: %{
          code: %Schema{type: :string},
          message: %Schema{type: :string},
          details: %Schema{type: :object, additionalProperties: true}
        },
        required: [:code, :message]
      }
    },
    required: [:error],
    example: %{
      "error" => %{
        "code" => "not_found",
        "message" => "Not found",
        "details" => %{}
      }
    }
  })
end
