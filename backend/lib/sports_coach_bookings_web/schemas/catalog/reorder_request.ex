defmodule SportsCoachBookingsWeb.Schemas.Catalog.ReorderRequest do
  @moduledoc "An ordered list of ids for a reorder endpoint."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReorderRequest",
    type: :object,
    properties: %{
      ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
    },
    required: [:ids]
  })
end
