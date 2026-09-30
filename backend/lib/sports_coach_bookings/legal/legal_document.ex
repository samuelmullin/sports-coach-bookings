defmodule SportsCoachBookings.Legal.LegalDocument do
  @moduledoc """
  A versioned tenant-owned legal document (terms of service, privacy policy, or
  any future kind). Owned by the portal legal-documents work.

  Exactly one version per `(tenant, kind)` may be `active` at a time; publishing
  a new version flips the previous one to inactive in the same transaction.
  Older versions are retained for historical reference.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "legal_documents" do
    field :tenant_id, :binary_id
    field :kind, :string
    field :title, :string
    field :body_markdown, :string
    field :version, :integer
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :kind, :title, :body_markdown, :version, :active])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :kind,
      :title,
      :body_markdown,
      :version,
      :active
    ])
    |> Ecto.Changeset.validate_number(:version, greater_than: 0)
    |> Ecto.Changeset.validate_length(:body_markdown, min: 1)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :kind, :version])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :kind],
      name: :legal_documents_one_active_per_kind,
      message: "already has an active version"
    )
  end
end
