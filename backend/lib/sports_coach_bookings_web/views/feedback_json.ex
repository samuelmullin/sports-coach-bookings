defmodule SportsCoachBookingsWeb.FeedbackJSON do
  @moduledoc "Serialises coach feedback, rosters, and skill tags."

  alias SportsCoachBookings.Feedback.Revision
  alias SportsCoachBookings.Feedback.SessionFeedback
  alias SportsCoachBookings.Feedback.SkillTag
  alias SportsCoachBookingsWeb.PlayersJSON
  alias SportsCoachBookingsWeb.SchedulingJSON

  @doc "Serialises a feedback row."
  @spec feedback(SessionFeedback.t()) :: map()
  def feedback(%SessionFeedback{} = feedback) do
    %{
      id: feedback.id,
      session_id: feedback.session_id,
      player_id: feedback.player_id,
      coach_id: feedback.coach_id,
      body: feedback.body,
      skill_ratings: feedback.skill_ratings,
      focus_next: feedback.focus_next,
      visibility: to_string(feedback.visibility),
      shared_at: datetime(feedback.shared_at),
      edited_at: datetime(feedback.edited_at),
      inserted_at: datetime(feedback.inserted_at),
      updated_at: datetime(feedback.updated_at)
    }
  end

  @doc "Serialises a compact feedback row for roster/summary contexts."
  @spec feedback_summary(SessionFeedback.t()) :: map()
  def feedback_summary(%SessionFeedback{} = feedback) do
    %{
      id: feedback.id,
      session_id: feedback.session_id,
      player_id: feedback.player_id,
      coach_id: feedback.coach_id,
      visibility: to_string(feedback.visibility),
      shared_at: datetime(feedback.shared_at),
      edited_at: datetime(feedback.edited_at)
    }
  end

  @doc "Serialises a revision snapshot."
  @spec revision(Revision.t()) :: map()
  def revision(%Revision{} = revision) do
    %{
      id: revision.id,
      feedback_id: revision.feedback_id,
      revision: revision.revision,
      body: revision.body,
      skill_ratings: revision.skill_ratings,
      focus_next: revision.focus_next,
      visibility: revision.visibility,
      shared_at: datetime(revision.shared_at),
      notify: revision.notify,
      editor_type: revision.editor_type,
      editor_id: revision.editor_id,
      inserted_at: datetime(revision.inserted_at)
    }
  end

  @doc "Serialises a skill tag."
  @spec skill_tag(SkillTag.t()) :: map()
  def skill_tag(%SkillTag{} = tag) do
    %{
      id: tag.id,
      name: tag.name,
      slug: tag.slug,
      position: tag.position,
      active: tag.active
    }
  end

  @doc "Serialises the coach player payload (player detail + recent feedback)."
  @spec coach_player(map()) :: map()
  def coach_player(%{player: player, feedback: feedback}) do
    %{
      player: PlayersJSON.player_detail(player),
      feedback: Enum.map(feedback, &feedback/1)
    }
  end

  @doc "Serialises a session entry (delegates to SchedulingJSON)."
  @spec session_entry(map()) :: map()
  def session_entry(entry), do: SchedulingJSON.calendar_entry(entry)

  @doc "Serialises a session's roster with player summaries and feedback."
  @spec roster([map()]) :: map()
  def roster(rows) do
    %{
      data:
        Enum.map(rows, fn row ->
          %{
            booking_id: row.booking_id,
            player_id: row.player_id,
            player: row.player,
            status: to_string(row.status),
            payment_method: to_string(row.payment_method),
            credits_used: row.credits_used,
            hold_expires_at: datetime(row.hold_expires_at),
            feedback: Enum.map(row.feedback, &feedback_summary/1)
          }
        end)
    }
  end

  @doc "Serialises a bulk attendance result."
  @spec attendance([map()]) :: map()
  def attendance(results) do
    %{data: Enum.map(results, &attendance_row/1)}
  end

  @doc "Wraps serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp attendance_row(row) do
    %{booking_id: row.booking_id, status: row.status, ok: row.ok, error: row.error}
  end

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
