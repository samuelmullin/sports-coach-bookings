defmodule SportsCoachBookingsWeb.Schemas.Scheduling do
  @moduledoc """
  Inline OpenApiSpex schemas for the WP-11 scheduling endpoints.
  """

  alias OpenApiSpex.Schema

  def datetime, do: %Schema{type: :string, format: :"date-time", nullable: true}

  def warning do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string, enum: ["venue_overlap", "coach_double_booked"]},
        session_id: %Schema{type: :string, format: :uuid},
        conflicting_session_id: %Schema{type: :string, format: :uuid},
        membership_id: %Schema{type: :string, format: :uuid, nullable: true},
        starts_at: datetime()
      }
    }
  end

  def offering_summary do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        slug: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        format: %Schema{type: :string, enum: ["private", "semi_private", "group"]},
        duration_minutes: %Schema{type: :integer},
        min_age: %Schema{type: :integer, nullable: true},
        max_age: %Schema{type: :integer, nullable: true},
        default_capacity: %Schema{type: :integer},
        credit_cost: %Schema{type: :integer},
        drop_in_price: %Schema{type: :integer, nullable: true},
        bookable_until_minutes_before: %Schema{type: :integer},
        bookable_from_days_ahead: %Schema{type: :integer, nullable: true}
      }
    }
  end

  def venue_summary do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        timezone: %Schema{type: :string}
      }
    }
  end

  def coach do
    %Schema{
      type: :object,
      properties: %{
        membership_id: %Schema{type: :string, format: :uuid},
        display_name: %Schema{type: :string, nullable: true},
        role: %Schema{type: :string}
      }
    }
  end

  def session do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        offering_id: %Schema{type: :string, format: :uuid},
        venue_id: %Schema{type: :string, format: :uuid},
        starts_at: datetime(),
        ends_at: datetime(),
        capacity: %Schema{type: :integer},
        booked_count: %Schema{type: :integer},
        held_count: %Schema{type: :integer},
        seats_left: %Schema{type: :integer},
        status: %Schema{type: :string, enum: ["scheduled", "cancelled", "completed"]},
        visibility: %Schema{type: :string, enum: ["public", "hidden"]},
        title_override: %Schema{type: :string, nullable: true},
        notes_public: %Schema{type: :string, nullable: true},
        notes_staff: %Schema{type: :string, nullable: true},
        show_coaches: %Schema{type: :boolean},
        series_id: %Schema{type: :string, format: :uuid, nullable: true},
        cancel_reason: %Schema{type: :string, nullable: true},
        inserted_at: datetime(),
        updated_at: datetime()
      }
    }
  end

  def calendar_entry do
    %Schema{
      type: :object,
      properties: %{
        session: session(),
        offering: offering_summary(),
        venue: venue_summary(),
        coaches: %Schema{type: :array, items: coach()},
        seats_left: %Schema{type: :integer},
        bookable: %Schema{type: :boolean},
        not_bookable_reason: %Schema{
          type: :string,
          nullable: true,
          enum: ["full", "too_late", "too_early", "cancelled"]
        },
        already_booked: %Schema{type: :boolean},
        warnings: %Schema{type: :array, items: warning()}
      }
    }
  end

  def session_detail do
    %Schema{
      type: :object,
      properties:
        Map.put(
          calendar_entry().properties,
          :roster,
          %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}}
        )
    }
  end

  def session_list_response do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: session()},
        next_cursor: %Schema{type: :string, nullable: true}
      }
    }
  end

  def calendar_list_response do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: calendar_entry()},
        next_cursor: %Schema{type: :string, nullable: true}
      }
    }
  end

  def series do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        weekdays: %Schema{type: :array, items: %Schema{type: :integer}},
        start_time_local: %Schema{type: :string, nullable: true},
        duration_minutes: %Schema{type: :integer},
        starts_on: %Schema{type: :string, format: :date, nullable: true},
        ends_on: %Schema{type: :string, format: :date, nullable: true},
        timezone: %Schema{type: :string},
        offering_id: %Schema{type: :string, format: :uuid},
        venue_id: %Schema{type: :string, format: :uuid},
        inserted_at: datetime(),
        updated_at: datetime()
      }
    }
  end

  def session_create_response do
    %Schema{
      type: :object,
      properties: %{
        session: session(),
        warnings: %Schema{type: :array, items: warning()}
      }
    }
  end

  def session_edit_response do
    session_create_response()
  end

  def series_create_response do
    %Schema{
      type: :object,
      properties: %{
        series: series(),
        sessions: %Schema{type: :array, items: session()},
        warnings: %Schema{type: :array, items: warning()}
      }
    }
  end

  def series_edit_response do
    %Schema{
      type: :object,
      properties: %{
        series: %Schema{type: :object, nullable: true},
        sessions: %Schema{type: :array, items: session()},
        warnings: %Schema{type: :array, items: warning()}
      }
    }
  end

  def cancel_response do
    %Schema{
      type: :object,
      properties: %{
        session: session(),
        impact: %Schema{
          type: :object,
          properties: %{
            booked_count: %Schema{type: :integer},
            held_count: %Schema{type: :integer}
          }
        }
      }
    }
  end

  def session_request do
    %Schema{
      type: :object,
      properties: %{
        offering_id: %Schema{type: :string, format: :uuid},
        venue_id: %Schema{type: :string, format: :uuid},
        starts_at: datetime(),
        ends_at: datetime(),
        capacity: %Schema{type: :integer},
        visibility: %Schema{type: :string, enum: ["public", "hidden"]},
        title_override: %Schema{type: :string, nullable: true},
        notes_public: %Schema{type: :string, nullable: true},
        notes_staff: %Schema{type: :string, nullable: true},
        show_coaches: %Schema{type: :boolean, nullable: true},
        coach_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
      },
      required: [:offering_id, :venue_id, :starts_at]
    }
  end

  def series_request do
    opts = session_request()

    %Schema{
      type: :object,
      properties:
        Map.merge(opts.properties, %{
          weekdays: %Schema{type: :array, items: %Schema{type: :integer}},
          start_time_local: %Schema{type: :string},
          duration_minutes: %Schema{type: :integer},
          starts_on: %Schema{type: :string, format: :date},
          ends_on: %Schema{type: :string, format: :date, nullable: true},
          timezone: %Schema{type: :string, nullable: true}
        }),
      required: [:offering_id, :venue_id, :weekdays, :start_time_local, :starts_on]
    }
  end

  def reschedule_request do
    %Schema{
      type: :object,
      properties: %{
        starts_at: datetime(),
        ends_at: datetime(),
        venue_id: %Schema{type: :string, format: :uuid}
      },
      required: [:starts_at]
    }
  end

  def cancel_request do
    %Schema{type: :object, properties: %{reason: %Schema{type: :string, nullable: true}}}
  end

  def series_edit_request do
    %Schema{
      type: :object,
      properties: %{
        scope: %Schema{type: :string, enum: ["single", "following", "all"]},
        confirm: %Schema{type: :boolean},
        capacity: %Schema{type: :integer},
        visibility: %Schema{type: :string, enum: ["public", "hidden"]},
        show_coaches: %Schema{type: :boolean, nullable: true},
        start_time_local: %Schema{type: :string},
        duration_minutes: %Schema{type: :integer},
        timezone: %Schema{type: :string, nullable: true},
        venue_id: %Schema{type: :string, format: :uuid},
        notes_public: %Schema{type: :string, nullable: true},
        notes_staff: %Schema{type: :string, nullable: true},
        coach_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
      },
      required: [:scope]
    }
  end
end
