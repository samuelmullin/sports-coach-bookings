defmodule SportsCoachBookings.Scheduling.SessionCoach do
  @moduledoc "Join between a session and a staff membership assigned to coach it."

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Scheduling.Session

  @type t :: %__MODULE__{}

  schema "session_coaches" do
    field :tenant_id, :binary_id
    # Cross-context (Staff membership).
    field :membership_id, :binary_id
    field :lead, :boolean, default: false

    belongs_to :session, Session

    timestamps()
  end

  @doc false
  def changeset(session_coach, attrs) do
    session_coach
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :session_id, :membership_id, :lead])
    |> Ecto.Changeset.validate_required([:tenant_id, :session_id, :membership_id])
    |> Ecto.Changeset.unique_constraint([:session_id, :membership_id])
  end
end
