defmodule SportsCoachBookingsWeb.Schemas.Payments do
  @moduledoc "OpenApiSpex schemas for the WP-04 payments endpoints."

  alias OpenApiSpex.Schema

  @doc "The resolved tenant's provider-connection status."
  def connect_status do
    %Schema{
      type: :object,
      properties: %{
        provider: %Schema{type: :string},
        account_ref: %Schema{type: :string, nullable: true},
        status: %Schema{
          type: :string,
          enum: ["not_connected", "pending", "restricted", "enabled"]
        },
        charges_enabled: %Schema{type: :boolean},
        payouts_enabled: %Schema{type: :boolean},
        requirements: %Schema{type: :object, additionalProperties: true},
        platform_fee_bps: %Schema{type: :integer}
      },
      required: [:provider, :status, :charges_enabled, :payouts_enabled, :platform_fee_bps]
    }
  end

  @doc "A hosted onboarding redirect."
  def onboarding do
    %Schema{
      type: :object,
      properties: %{url: %Schema{type: :string, format: :uri}},
      required: [:url]
    }
  end
end
