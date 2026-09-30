defmodule SportsCoachBookings.Repo.Migrations.FeedbackCreateSessionFeedback do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :session_feedback do
      # Cross-context (Scheduling), plain uuid, no FK.
      add :session_id, :binary_id, null: false
      # Cross-context (Players), plain uuid, no FK.
      add :player_id, :binary_id, null: false
      # Cross-context (Staff membership), plain uuid, no FK.
      add :coach_id, :binary_id, null: false

      add :body, :text, null: false
      add :skill_ratings, :map, null: false, default: %{}
      add :focus_next, :text

      # Ecto enum: internal | shared.
      add :visibility, :string, null: false, default: "internal"
      add :shared_at, :utc_datetime_usec
      add :edited_at, :utc_datetime_usec
    end

    # One feedback per (session, player, coach).
    create unique_index(
             :session_feedback,
             [:tenant_id, :session_id, :player_id, :coach_id],
             name: :session_feedback_one_per_coach
           )

    create index(:session_feedback, [:tenant_id, :player_id, :inserted_at])
    create index(:session_feedback, [:tenant_id, :coach_id, :inserted_at])
    create index(:session_feedback, [:tenant_id, :session_id])

    create constraint(
             :session_feedback,
             :session_feedback_visibility_check,
             check: "visibility in ('internal', 'shared')"
           )
  end
end
