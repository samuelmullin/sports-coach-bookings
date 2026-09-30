defmodule SportsCoachBookings.Notifications.DeliveryRef do
  @moduledoc """
  Platform lookup from a provider message id to its tenant and delivery.

  Written when a delivery is accepted by the provider. It lets a webhook resolve
  the owning tenant before entering tenant context (and RLS). No `tenant_id`
  RLS policy: this table is platform-level.
  """

  use SportsCoachBookings.Core.Schema

  @type t :: %__MODULE__{}

  schema "notifications_delivery_refs" do
    field :provider, :string
    field :provider_ref, :string
    field :tenant_id, :binary_id
    field :delivery_id, :binary_id

    timestamps()
  end

  @doc false
  def changeset(ref, attrs) do
    ref
    |> Ecto.Changeset.cast(attrs, [:provider, :provider_ref, :tenant_id, :delivery_id])
    |> Ecto.Changeset.validate_required([:provider, :provider_ref, :tenant_id, :delivery_id])
    |> Ecto.Changeset.unique_constraint([:provider, :provider_ref])
  end
end
