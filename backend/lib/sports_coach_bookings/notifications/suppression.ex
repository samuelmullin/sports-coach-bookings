defmodule SportsCoachBookings.Notifications.Suppression do
  @moduledoc """
  Addresses that must not receive mail (hard bounce or complaint). Tenant-owned
  (RLS). Password-reset mail is exempt at send time.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @reasons [:bounce, :complaint]

  schema "suppressions" do
    field :tenant_id, :binary_id
    field :email, :string
    field :reason, Ecto.Enum, values: @reasons

    timestamps()
  end

  @doc false
  def changeset(suppression, attrs) do
    suppression
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :email, :reason])
    |> Ecto.Changeset.validate_required([:tenant_id, :email, :reason])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :email])
  end

  @doc "The suppression reasons."
  @spec reasons() :: [atom()]
  def reasons, do: @reasons
end
