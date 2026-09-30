defmodule SportsCoachBookingsWeb.Schemas.Feedback do
  @moduledoc "Inline OpenApiSpex schemas for the WP-15 coach/feedback endpoints."

  alias OpenApiSpex.Schema

  def datetime, do: %Schema{type: :string, format: :"date-time", nullable: true}

  def skill_tag do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        slug: %Schema{type: :string},
        position: %Schema{type: :integer},
        active: %Schema{type: :boolean}
      },
      required: [:id, :name, :slug]
    }
  end

  def skill_tag_list do
    %Schema{
      type: :object,
      properties: %{data: %Schema{type: :array, items: skill_tag()}},
      required: [:data]
    }
  end

  def create_skill_tag_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        slug: %Schema{type: :string},
        position: %Schema{type: :integer, nullable: true},
        active: %Schema{type: :boolean, nullable: true}
      },
      required: [:name, :slug]
    }
  end

  def feedback do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        session_id: %Schema{type: :string, format: :uuid},
        player_id: %Schema{type: :string, format: :uuid},
        coach_id: %Schema{type: :string, format: :uuid},
        body: %Schema{type: :string},
        skill_ratings: %Schema{type: :object, additionalProperties: true},
        focus_next: %Schema{type: :string, nullable: true},
        visibility: %Schema{type: :string, enum: ["internal", "shared"]},
        shared_at: datetime(),
        edited_at: datetime(),
        inserted_at: datetime(),
        updated_at: datetime()
      },
      required: [:id, :session_id, :player_id, :coach_id, :body, :visibility]
    }
  end

  def feedback_summary do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        session_id: %Schema{type: :string, format: :uuid},
        player_id: %Schema{type: :string, format: :uuid},
        coach_id: %Schema{type: :string, format: :uuid},
        visibility: %Schema{type: :string, enum: ["internal", "shared"]},
        shared_at: datetime(),
        edited_at: datetime()
      },
      required: [:id, :session_id, :player_id, :coach_id, :visibility]
    }
  end

  def feedback_list do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: feedback()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end

  def create_request do
    %Schema{
      type: :object,
      properties: %{
        session_id: %Schema{type: :string, format: :uuid},
        player_id: %Schema{type: :string, format: :uuid},
        coach_id: %Schema{type: :string, format: :uuid, nullable: true},
        body: %Schema{type: :string},
        skill_ratings: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :integer, minimum: 1, maximum: 5},
          nullable: true
        },
        focus_next: %Schema{type: :string, nullable: true},
        visibility: %Schema{type: :string, enum: ["internal", "shared"], nullable: true}
      },
      required: [:session_id, :player_id, :body]
    }
  end

  def edit_request do
    %Schema{
      type: :object,
      properties: %{
        body: %Schema{type: :string, nullable: true},
        skill_ratings: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :integer, minimum: 1, maximum: 5},
          nullable: true
        },
        focus_next: %Schema{type: :string, nullable: true},
        visibility: %Schema{type: :string, enum: ["internal", "shared"], nullable: true},
        notify: %Schema{type: :boolean, nullable: true}
      }
    }
  end

  def attendance_request do
    %Schema{
      type: :object,
      properties: %{
        attendance: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              booking_id: %Schema{type: :string, format: :uuid},
              status: %Schema{type: :string, enum: ["attended", "no_show"]}
            },
            required: [:booking_id, :status]
          }
        }
      },
      required: [:attendance]
    }
  end

  def attendance_response do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              booking_id: %Schema{type: :string, format: :uuid, nullable: true},
              status: %Schema{type: :string, nullable: true},
              ok: %Schema{type: :boolean},
              error: %Schema{type: :string, nullable: true}
            },
            required: [:ok]
          }
        }
      },
      required: [:data]
    }
  end

  def roster_response do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              booking_id: %Schema{type: :string, format: :uuid},
              player_id: %Schema{type: :string, format: :uuid},
              player: %Schema{type: :object, nullable: true, additionalProperties: true},
              status: %Schema{type: :string},
              payment_method: %Schema{type: :string},
              credits_used: %Schema{type: :integer},
              hold_expires_at: datetime(),
              feedback: %Schema{type: :array, items: feedback_summary()}
            },
            required: [:booking_id, :player_id, :status]
          }
        }
      },
      required: [:data]
    }
  end

  def coach_player_response do
    %Schema{
      type: :object,
      properties: %{
        player: %Schema{type: :object, additionalProperties: true},
        feedback: %Schema{type: :array, items: feedback()}
      },
      required: [:player, :feedback]
    }
  end

  def revisions_response do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              feedback_id: %Schema{type: :string, format: :uuid},
              revision: %Schema{type: :integer},
              body: %Schema{type: :string},
              skill_ratings: %Schema{type: :object, additionalProperties: true},
              focus_next: %Schema{type: :string, nullable: true},
              visibility: %Schema{type: :string},
              shared_at: datetime(),
              notify: %Schema{type: :boolean},
              editor_type: %Schema{type: :string, nullable: true},
              editor_id: %Schema{type: :string, format: :uuid, nullable: true},
              inserted_at: datetime()
            }
          }
        }
      },
      required: [:data]
    }
  end
end
