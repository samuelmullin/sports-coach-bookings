defmodule SportsCoachBookingsWeb.Schemas.Policies.PolicyRules do
  @moduledoc "Embedded cancellation/rebooking rules."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  @outcome %Schema{
    type: :object,
    properties: %{
      credit_outcome: %Schema{type: :string, enum: ["return", "forfeit"]},
      money_refund_pct: %Schema{type: :integer, minimum: 0, maximum: 100}
    },
    required: [:credit_outcome, :money_refund_pct]
  }

  OpenApiSpex.schema(%{
    title: "PolicyRules",
    type: :object,
    properties: %{
      cancellation_tiers: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            min_hours_before: %Schema{type: :integer, minimum: 0},
            credit_outcome: %Schema{type: :string, enum: ["return", "forfeit"]},
            money_refund_pct: %Schema{type: :integer, minimum: 0, maximum: 100}
          },
          required: [:min_hours_before, :credit_outcome, :money_refund_pct]
        }
      },
      no_show: @outcome,
      late_cancel_counts_as_no_show: %Schema{type: :boolean},
      rebook: %Schema{
        type: :object,
        properties: %{
          allowed: %Schema{type: :boolean},
          min_hours_before: %Schema{type: :integer, minimum: 0},
          max_rebooks_per_booking: %Schema{type: :integer, minimum: 0, nullable: true},
          same_offering_only: %Schema{type: :boolean}
        },
        required: [:allowed, :min_hours_before, :same_offering_only]
      },
      provider_cancelled: @outcome
    },
    required: [
      :cancellation_tiers,
      :no_show,
      :late_cancel_counts_as_no_show,
      :rebook,
      :provider_cancelled
    ]
  })
end
