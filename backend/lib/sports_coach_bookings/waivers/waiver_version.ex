defmodule SportsCoachBookings.Waivers.WaiverVersion do
  @moduledoc """
  A specific published/draft text of a waiver template. Owned by WP-07.

  Once a version has been published its `body_markdown`, `content_sha256`,
  `version`, and `waiver_template_id` are immutable. This is enforced both by
  `changeset/2` and by a Postgres trigger (`waiver_versions_immutable`).
  Publishing a new version moves the previous published version to
  `:superseded`.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Waivers.WaiverTemplate

  @type t :: %__MODULE__{}

  @statuses [:draft, :published, :superseded]

  schema "waiver_versions" do
    field :tenant_id, :binary_id
    belongs_to :waiver_template, WaiverTemplate
    field :version, :integer
    field :body_markdown, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :published_at, :utc_datetime_usec
    field :content_sha256, :string

    timestamps()
  end

  @doc false
  def changeset(version, attrs) do
    version
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :waiver_template_id,
      :version,
      :body_markdown,
      :status,
      :published_at,
      :content_sha256
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :waiver_template_id,
      :version,
      :body_markdown,
      :content_sha256
    ])
    |> Ecto.Changeset.validate_number(:version, greater_than: 0)
    |> Ecto.Changeset.validate_length(:body_markdown, min: 1)
    |> Ecto.Changeset.unique_constraint([:waiver_template_id, :version])
    |> Ecto.Changeset.unique_constraint([:waiver_template_id],
      name: :waiver_versions_one_published_per_template,
      message: "already has a published version"
    )
    |> lock_published_body()
  end

  @doc "The version's body is immutable once the version has been published."
  @spec immutable?(t()) :: boolean()
  def immutable?(%__MODULE__{status: status}), do: status in [:published, :superseded]

  defp lock_published_body(%Ecto.Changeset{data: %{status: status}} = changeset)
       when status in [:published, :superseded] do
    if Ecto.Changeset.get_change(changeset, :body_markdown) do
      Ecto.Changeset.add_error(
        changeset,
        :body_markdown,
        "cannot be edited after the version is published"
      )
    else
      changeset
    end
  end

  defp lock_published_body(changeset), do: changeset
end
