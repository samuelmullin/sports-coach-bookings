defmodule SportsCoachBookingsWeb.Schemas.Bookings do
  @moduledoc "OpenApiSpex schemas for the WP-14 booking endpoints."

  alias OpenApiSpex.Schema

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

  def booking do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        session_id: %Schema{type: :string, format: :uuid},
        player_id: %Schema{type: :string, format: :uuid},
        household_id: %Schema{type: :string, format: :uuid},
        status: %Schema{
          type: :string,
          enum: ["held", "confirmed", "cancelled", "attended", "no_show"]
        },
        payment_method: %Schema{type: :string, enum: ["credits", "paid", "comp"]},
        credits_used: %Schema{type: :integer},
        order_line_id: %Schema{type: :string, format: :uuid, nullable: true},
        rebook_count: %Schema{type: :integer},
        rebooked_from_id: %Schema{type: :string, format: :uuid, nullable: true},
        rebooked_to_id: %Schema{type: :string, format: :uuid, nullable: true},
        hold_expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
        cancelled_at: %Schema{type: :string, format: :"date-time", nullable: true},
        free_change_until: %Schema{type: :string, format: :"date-time", nullable: true},
        cancel_outcome: %Schema{type: :object, nullable: true, additionalProperties: true},
        paid_amount: %Schema{type: :integer},
        currency: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :session_id, :player_id, :status, :payment_method]
    }
  end

  def booking_entry do
    %Schema{
      type: :object,
      properties: %{
        booking: booking(),
        session: %Schema{type: :object, nullable: true, additionalProperties: true},
        offering: %Schema{type: :object, nullable: true, additionalProperties: true}
      },
      required: [:booking]
    }
  end

  def booking_list, do: list(booking_entry())

  def create_request do
    %Schema{
      type: :object,
      properties: %{
        player_id: %Schema{type: :string, format: :uuid},
        session_id: %Schema{type: :string, format: :uuid},
        method: %Schema{type: :string, enum: ["credits", "paid", "comp"]},
        override: %Schema{type: :boolean, nullable: true},
        reason: %Schema{type: :string, nullable: true}
      },
      required: [:player_id, :session_id, :method]
    }
  end

  def cancel_request do
    %Schema{
      type: :object,
      properties: %{
        reason: %Schema{type: :string, nullable: true},
        outcome: %Schema{
          type: :string,
          nullable: true,
          enum: [
            "full_return",
            "forfeit",
            "credit_return",
            "provider_cancelled",
            "partial_refund"
          ]
        },
        refund_pct: %Schema{type: :integer, nullable: true}
      }
    }
  end

  def rebook_request do
    %Schema{
      type: :object,
      properties: %{target_session_id: %Schema{type: :string, format: :uuid}},
      required: [:target_session_id]
    }
  end

  def attendance_request do
    %Schema{
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["attended", "no_show"]}},
      required: [:status]
    }
  end

  def cancel_preview do
    %Schema{
      type: :object,
      properties: %{
        booking: booking(),
        already_cancelled: %Schema{type: :boolean},
        outcome: %Schema{type: :object, additionalProperties: true}
      },
      required: [:booking, :outcome]
    }
  end

  def rebook_options do
    %Schema{
      type: :object,
      properties: %{
        allowed: %Schema{type: :boolean},
        reason: %Schema{type: :string, nullable: true},
        sessions: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              session: %Schema{type: :object, additionalProperties: true},
              offering: %Schema{type: :object, nullable: true, additionalProperties: true}
            }
          }
        }
      },
      required: [:allowed, :sessions]
    }
  end

  def roster_response do
    %Schema{
      type: :object,
      properties: %{data: %Schema{type: :array, items: roster_row()}},
      required: [:data]
    }
  end

  def roster_row do
    %Schema{
      type: :object,
      properties: %{
        booking_id: %Schema{type: :string, format: :uuid},
        player_id: %Schema{type: :string, format: :uuid},
        player_name: %Schema{type: :string, nullable: true},
        status: %Schema{type: :string},
        payment_method: %Schema{type: :string},
        credits_used: %Schema{type: :integer},
        hold_expires_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:booking_id, :player_id, :status]
    }
  end

  def history_response do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              kind: %Schema{type: :string},
              actor_type: %Schema{type: :string, nullable: true},
              actor_id: %Schema{type: :string, format: :uuid, nullable: true},
              data: %Schema{type: :object, additionalProperties: true},
              inserted_at: %Schema{type: :string, format: :"date-time", nullable: true}
            }
          }
        }
      },
      required: [:data]
    }
  end
end
