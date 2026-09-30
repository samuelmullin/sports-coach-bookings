defmodule SportsCoachBookings.Notifications.WebhookEvent do
  @moduledoc """
  Durable record of a provider webhook event. Platform table (no `tenant_id`, no
  RLS); the unique `(provider, event_id)` pair makes replays a no-op.
  """

  use SportsCoachBookings.Core.Schema

  @type t :: %__MODULE__{}

  schema "notifications_webhook_events" do
    field :provider, :string
    field :event_id, :string
    field :type, :string
    field :payload, :map
    field :processed_at, :utc_datetime_usec
    field :error, :string

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> Ecto.Changeset.cast(attrs, [:provider, :event_id, :type, :payload, :processed_at, :error])
    |> Ecto.Changeset.validate_required([:provider, :event_id, :type])
    |> Ecto.Changeset.unique_constraint([:provider, :event_id])
  end
end
