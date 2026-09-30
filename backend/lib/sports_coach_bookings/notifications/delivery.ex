defmodule SportsCoachBookings.Notifications.Delivery do
  @moduledoc """
  One delivery row per recipient of a message. Tenant-owned (RLS).

  Status transitions: `queued -> sent -> delivered | bounced | complained`,
  or `queued -> failed` after retries, or `suppressed` when the recipient is
  suppressed or has opted out of the category.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Notifications.Message

  @type t :: %__MODULE__{}

  @statuses [:queued, :sent, :delivered, :bounced, :complained, :failed, :suppressed]
  @recipient_types [:customer_user, :staff_user, :email]

  schema "deliveries" do
    field :tenant_id, :binary_id
    field :recipient_type, Ecto.Enum, values: @recipient_types
    field :recipient_id, :binary_id
    field :email, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :provider_ref, :string
    field :sent_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :bounced_at, :utc_datetime_usec
    field :error, :string

    belongs_to :message, Message, foreign_key: :message_id, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :message_id,
      :recipient_type,
      :recipient_id,
      :email,
      :status,
      :provider_ref,
      :sent_at,
      :delivered_at,
      :bounced_at,
      :error
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :message_id, :recipient_type, :email])
  end

  @doc "The statuses a delivery can be in."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "The recipient types a delivery can target."
  @spec recipient_types() :: [atom()]
  def recipient_types, do: @recipient_types

  @doc "A delivery that should not be retried as-is."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}), do: status in [:delivered, :complained]
end
