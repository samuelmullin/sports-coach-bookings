defmodule SportsCoachBookings.Feedback.SkillTag do
  @moduledoc """
  A tenant-configurable skill a coach can rate on a feedback row. Owned by WP-15.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "feedback_skill_tags" do
    field :tenant_id, :binary_id
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(skill_tag, attrs) do
    skill_tag
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :name, :slug, :position, :active])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :slug])
    |> Ecto.Changeset.validate_length(:name, max: 100)
    |> Ecto.Changeset.validate_length(:slug, max: 100)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :slug])
  end
end
