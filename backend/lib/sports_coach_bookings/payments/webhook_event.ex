defmodule SportsCoachBookings.Payments.WebhookEvent do
  @moduledoc """
  Durable record of a payment-provider webhook event. Platform table (no
  `tenant_id`, no RLS); the unique `(provider, event_id)` pair makes replays a
  no-op. The tenant that owns the event is resolved from the payload/account and
  carried in the processing job's args.
  """

  use SportsCoachBookings.Core.Schema

  @type t :: %__MODULE__{}

  schema "payments_webhook_events" do
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

  @doc "True once the event has been processed by the worker."
  @spec processed?(t()) :: boolean()
  def processed?(%__MODULE__{processed_at: nil}), do: false
  def processed?(%__MODULE__{}), do: true
end
