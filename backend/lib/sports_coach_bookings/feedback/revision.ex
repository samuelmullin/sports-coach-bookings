defmodule SportsCoachBookings.Feedback.Revision do
  @moduledoc """
  An append-only snapshot of a feedback row taken immediately before an edit.
  Owned by WP-15.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Feedback.SessionFeedback

  @type t :: %__MODULE__{}

  schema "feedback_revisions" do
    field :tenant_id, :binary_id
    field :revision, :integer, default: 1
    field :body, :string
    field :skill_ratings, :map, default: %{}
    field :focus_next, :string
    field :visibility, :string
    field :shared_at, :utc_datetime_usec
    field :notify, :boolean, default: false
    field :editor_type, :string
    field :editor_id, :binary_id

    belongs_to :feedback, SessionFeedback, foreign_key: :feedback_id

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(revision, attrs) do
    revision
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :feedback_id,
      :revision,
      :body,
      :skill_ratings,
      :focus_next,
      :visibility,
      :shared_at,
      :notify,
      :editor_type,
      :editor_id
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :feedback_id, :body, :visibility])
  end
end
