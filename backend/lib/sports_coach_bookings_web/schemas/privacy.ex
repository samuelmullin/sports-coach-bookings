defmodule SportsCoachBookingsWeb.Schemas.Privacy do
  @moduledoc "OpenApiSpex schemas for the PIPEDA export and erasure endpoints."

  alias OpenApiSpex.Schema

  @doc "The household data export. Nested records mirror the portal resources."
  def export do
    list = fn description ->
      %Schema{
        type: :array,
        items: %Schema{type: :object, additionalProperties: true},
        description: description
      }
    end

    %Schema{
      type: :object,
      properties: %{
        generated_at: %Schema{type: :string, format: :"date-time"},
        household: %Schema{type: :object, additionalProperties: true},
        players:
          list.(
            "Each player with profile, contacts, pickups, medical info, waivers, shared feedback"
          ),
        bookings: list.("Booking history"),
        credit_lots: list.("Credit lots"),
        credit_ledger: list.("Credit ledger entries"),
        orders: list.("Orders with lines")
      },
      required: [:generated_at, :household, :players]
    }
  end

  def erase_request do
    %Schema{
      type: :object,
      properties: %{
        password: %Schema{type: :string, description: "The primary member's current password"},
        confirm: %Schema{type: :string, enum: ["ERASE"], description: "Must be the literal ERASE"}
      },
      required: [:password, :confirm]
    }
  end

  def erase_response do
    %Schema{
      type: :object,
      properties: %{
        players: %Schema{type: :integer},
        feedback: %Schema{type: :integer},
        accounts: %Schema{type: :integer},
        carts: %Schema{type: :integer},
        reservations: %Schema{type: :integer},
        scrubbed_messages: %Schema{type: :integer},
        waiver_pdfs: %Schema{
          type: :integer,
          description: "Stored waiver PDFs queued for deletion"
        }
      },
      required: [:players, :accounts]
    }
  end
end
