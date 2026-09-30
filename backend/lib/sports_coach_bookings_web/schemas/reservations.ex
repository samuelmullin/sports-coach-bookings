defmodule SportsCoachBookingsWeb.Schemas.Reservations do
  @moduledoc "OpenApiSpex schemas for the guest reservation endpoints."

  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Bookings

  def session_summary do
    %Schema{
      type: :object,
      properties: %{
        session_id: %Schema{type: :string, format: :uuid},
        starts_at: %Schema{type: :string, format: :"date-time", nullable: true},
        ends_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:session_id]
    }
  end

  def reservation do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        status: %Schema{type: :string, enum: ["active", "converted", "expired", "released"]},
        expires_at: %Schema{type: :string, format: :"date-time"},
        last_activity_at: %Schema{type: :string, format: :"date-time"},
        offering_id: %Schema{type: :string, format: :uuid, nullable: true},
        sessions: %Schema{type: :array, items: session_summary()}
      },
      required: [:id, :status, :expires_at, :last_activity_at, :sessions]
    }
  end

  def create_request do
    %Schema{
      type: :object,
      properties: %{
        sessions: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}},
        offering_id: %Schema{type: :string, format: :uuid, nullable: true}
      },
      required: [:sessions]
    }
  end

  def create_response do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        token: %Schema{type: :string},
        status: %Schema{type: :string, enum: ["active", "converted", "expired", "released"]},
        expires_at: %Schema{type: :string, format: :"date-time"},
        last_activity_at: %Schema{type: :string, format: :"date-time"},
        offering_id: %Schema{type: :string, format: :uuid, nullable: true},
        sessions: %Schema{type: :array, items: session_summary()}
      },
      required: [:id, :token, :status, :expires_at, :sessions]
    }
  end

  def extend_response do
    %Schema{
      type: :object,
      properties: %{
        expires_at: %Schema{type: :string, format: :"date-time"},
        last_activity_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:expires_at, :last_activity_at]
    }
  end

  def convert_request do
    %Schema{
      type: :object,
      properties: %{
        assignments: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              session_id: %Schema{type: :string, format: :uuid},
              player_id: %Schema{type: :string, format: :uuid},
              method: %Schema{type: :string, enum: ["credits", "paid"]}
            },
            required: [:session_id, :player_id, :method]
          }
        }
      },
      required: [:assignments]
    }
  end

  def convert_response do
    %Schema{
      type: :object,
      properties: %{
        bookings: %Schema{type: :array, items: Bookings.booking()}
      },
      required: [:bookings]
    }
  end
end
