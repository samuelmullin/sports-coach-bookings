defmodule SportsCoachBookingsWeb.Schemas.Policies.AssignmentRequest do
  @moduledoc "Assigns a policy to a list of offerings."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PolicyAssignmentRequest",
    type: :object,
    properties: %{
      offering_ids: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :uuid}
      }
    },
    required: [:offering_ids]
  })
end
