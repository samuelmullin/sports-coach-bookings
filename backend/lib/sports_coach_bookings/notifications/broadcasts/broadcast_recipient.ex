defmodule SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient do
  @moduledoc """
  One recipient of a broadcast. Tenant-owned (RLS). Owned by WP-17.

  The unique `(tenant_id, broadcast_id, email)` index plus the engine's
  per-recipient idempotency key make a re-run of a send a no-op for recipients
  already processed. `message_id`/`delivery_id` link to WP-05's delivery
  tracking for live history and stats.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast

  @type t :: %__MODULE__{}

  @recipient_types [:customer_user, :staff_user, :email]
  @statuses [:pending, :sent, :suppressed, :failed]

  schema "broadcast_recipients" do
    field :tenant_id, :binary_id
    field :recipient_type, Ecto.Enum, values: @recipient_types, default: :customer_user
    field :recipient_id, :binary_id
    field :email, :string
    field :household_id, :binary_id
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :batch_index, :integer, default: 0
    field :message_id, :binary_id
    field :delivery_id, :binary_id
    field :sent_at, :utc_datetime_usec
    field :error, :string

    belongs_to :broadcast, Broadcast, foreign_key: :broadcast_id, type: :binary_id

    timestamps()
  end

  @doc "The recipient statuses."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "The recipient types."
  @spec recipient_types() :: [atom()]
  def recipient_types, do: @recipient_types

  @doc false
  def changeset(recipient, attrs) do
    recipient
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :broadcast_id,
      :recipient_type,
      :recipient_id,
      :email,
      :household_id,
      :status,
      :batch_index,
      :message_id,
      :delivery_id,
      :sent_at,
      :error
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :broadcast_id, :recipient_type, :email])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :broadcast_id, :email])
  end
end
