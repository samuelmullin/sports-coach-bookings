defmodule SportsCoachBookings.Websites.ContactSubmission do
  @moduledoc "A public inquiry submitted through a tenant's hosted website."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}
  @statuses [:new, :read, :resolved]

  schema "website_contact_submissions" do
    field :tenant_id, :binary_id
    field :name, :string
    field :email, :string
    field :phone, :string
    field :company, :string
    field :subject, :string
    field :message, :string
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :resolved_at, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def create_changeset(submission, attrs) do
    submission
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :email,
      :phone,
      :company,
      :subject,
      :message
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :email, :message])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> Ecto.Changeset.validate_length(:name, max: 120)
    |> Ecto.Changeset.validate_length(:email, max: 320)
    |> Ecto.Changeset.validate_length(:phone, max: 40)
    |> Ecto.Changeset.validate_length(:company, max: 160)
    |> Ecto.Changeset.validate_length(:subject, max: 160)
    |> Ecto.Changeset.validate_format(:subject, ~r/^[^\r\n]*$/,
      message: "cannot contain line breaks"
    )
    |> Ecto.Changeset.validate_length(:message, min: 10, max: 5_000)
  end

  @doc false
  def status_changeset(submission, attrs) do
    submission
    |> Ecto.Changeset.cast(attrs, [:status])
    |> put_resolved_at()
  end

  defp put_resolved_at(changeset) do
    case Ecto.Changeset.get_change(changeset, :status) do
      :resolved -> Ecto.Changeset.put_change(changeset, :resolved_at, DateTime.utc_now())
      nil -> changeset
      _status -> Ecto.Changeset.put_change(changeset, :resolved_at, nil)
    end
  end
end
