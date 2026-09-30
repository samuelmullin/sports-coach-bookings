defmodule SportsCoachBookings.Feedback.SessionFeedback do
  @moduledoc """
  A coach's feedback about a player for a specific session. Owned by WP-15.

  One row per `(session, player, coach)`. `visibility` is `internal` until the
  author shares it, at which point `shared_at` is set and `feedback.submitted`
  is published exactly once (edits do not re-publish unless `notify: true`).
  Every edit snapshots the previous state into `feedback_revisions`.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Feedback.Revision

  @type t :: %__MODULE__{}

  @visibilities [:internal, :shared]
  @max_body_length 5_000
  @min_rating 1
  @max_rating 5

  schema "session_feedback" do
    field :tenant_id, :binary_id
    # Cross-context (Scheduling), plain uuid, no FK.
    field :session_id, :binary_id
    # Cross-context (Players), plain uuid, no FK.
    field :player_id, :binary_id
    # Cross-context (Staff membership), plain uuid, no FK.
    field :coach_id, :binary_id

    field :body, :string
    field :skill_ratings, :map, default: %{}
    field :focus_next, :string

    field :visibility, Ecto.Enum, values: @visibilities, default: :internal
    field :shared_at, :utc_datetime_usec
    field :edited_at, :utc_datetime_usec

    has_many :revisions, Revision, foreign_key: :feedback_id

    timestamps()
  end

  @doc "The allowed visibilities."
  @spec visibilities() :: [atom()]
  def visibilities, do: @visibilities

  @doc "Maximum body length in characters."
  @spec max_body_length() :: pos_integer()
  def max_body_length, do: @max_body_length

  @doc "The allowed rating range."
  @spec rating_range() :: Range.t()
  def rating_range, do: @min_rating..@max_rating

  @doc false
  def create_changeset(feedback, attrs) do
    feedback
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :session_id,
      :player_id,
      :coach_id,
      :body,
      :skill_ratings,
      :focus_next,
      :visibility
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :session_id,
      :player_id,
      :coach_id,
      :body
    ])
    |> Ecto.Changeset.validate_length(:body, min: 1, max: @max_body_length)
    |> Ecto.Changeset.validate_length(:focus_next, max: @max_body_length)
    |> Ecto.Changeset.unique_constraint(
      [:tenant_id, :session_id, :player_id, :coach_id],
      name: :session_feedback_one_per_coach
    )
  end

  @doc false
  def edit_changeset(feedback, attrs) do
    feedback
    |> Ecto.Changeset.cast(attrs, [:body, :skill_ratings, :focus_next, :visibility])
    |> Ecto.Changeset.validate_length(:body, min: 1, max: @max_body_length)
    |> Ecto.Changeset.validate_length(:focus_next, max: @max_body_length)
  end
end
