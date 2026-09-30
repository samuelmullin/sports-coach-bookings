defmodule SportsCoachBookingsWeb.Schemas.Credits do
  @moduledoc """
  Inline OpenApiSpex schemas for the WP-12 credit ledger endpoints, in the style
  of `SportsCoachBookingsWeb.Schemas.Api`.
  """

  alias OpenApiSpex.Schema

  @doc "A generic paginated list envelope around `item`."
  def list(item) do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: item},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end

  def balance_entry do
    %Schema{
      type: :object,
      properties: %{
        offering_id: %Schema{
          type: :string,
          nullable: true,
          description: "Offering id, or \"any\" for credits valid on any offering"
        },
        amount: %Schema{type: :integer},
        nearest_expiry: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:offering_id, :amount]
    }
  end

  def balance_response do
    %Schema{
      type: :object,
      properties: %{data: %Schema{type: :array, items: balance_entry()}},
      required: [:data]
    }
  end

  def lot do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        household_id: %Schema{type: :string, format: :uuid},
        source: %Schema{type: :string, enum: ["package_purchase", "admin_grant", "return_grace"]},
        order_line_id: %Schema{type: :string, format: :uuid, nullable: true},
        package_id: %Schema{type: :string, format: :uuid, nullable: true},
        eligible_offering_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}},
        quantity_granted: %Schema{type: :integer},
        remaining: %Schema{type: :integer},
        expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
        granted_at: %Schema{type: :string, format: :"date-time"},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :source, :quantity_granted, :remaining, :granted_at]
    }
  end

  def lot_list, do: list(lot())

  def ledger_entry do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        household_id: %Schema{type: :string, format: :uuid},
        credit_lot_id: %Schema{type: :string, format: :uuid},
        delta: %Schema{type: :integer},
        reason: %Schema{type: :string, enum: ["grant", "debit", "reversal", "expire", "adjust"]},
        booking_id: %Schema{type: :string, format: :uuid, nullable: true},
        reverses_entry_id: %Schema{type: :string, format: :uuid, nullable: true},
        actor_type: %Schema{type: :string, nullable: true},
        actor_id: %Schema{type: :string, format: :uuid, nullable: true},
        note: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :credit_lot_id, :delta, :reason]
    }
  end

  def ledger_entry_list, do: list(ledger_entry())

  def grant_request do
    %Schema{
      type: :object,
      properties: %{
        amount: %Schema{type: :integer, description: "Credits to grant (positive)"},
        note: %Schema{type: :string, nullable: true},
        validity_days: %Schema{type: :integer, nullable: true},
        eligible_offering_ids: %Schema{
          type: :array,
          items: %Schema{type: :string, format: :uuid}
        }
      },
      required: [:amount]
    }
  end

  def adjust_request do
    %Schema{
      type: :object,
      properties: %{
        lot_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Lot to adjust; omit to create a new admin grant"
        },
        delta: %Schema{type: :integer, description: "Signed change"},
        note: %Schema{type: :string, nullable: true}
      },
      required: [:delta]
    }
  end
end
