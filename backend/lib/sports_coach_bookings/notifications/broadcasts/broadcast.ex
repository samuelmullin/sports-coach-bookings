defmodule SportsCoachBookings.Notifications.Broadcasts.Broadcast do
  @moduledoc """
  A staff-authored broadcast email. Tenant-owned (RLS). Owned by WP-17.

  `segment` is the embedded targeting definition (see `Broadcasts.Segment`),
  `status` moves `draft -> scheduled -> sending -> sent` (or `cancelled` from
  draft/scheduled), and `stats` snapshots the delivery counts at send time.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient
  alias SportsCoachBookings.Notifications.Broadcasts.Segment

  @type t :: %__MODULE__{}

  @categories [:operational, :marketing]
  @statuses [:draft, :scheduled, :sending, :sent, :cancelled]

  schema "broadcasts" do
    field :tenant_id, :binary_id
    field :subject, :string
    field :body_markdown, :string
    field :category, Ecto.Enum, values: @categories, default: :marketing
    field :segment, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :scheduled_for, :utc_datetime_usec
    field :sent_at, :utc_datetime_usec
    field :created_by, :binary_id
    field :recipient_count, :integer, default: 0
    field :stats, :map, default: %{}

    has_many :recipients, BroadcastRecipient, foreign_key: :broadcast_id

    timestamps()
  end

  @doc "The broadcast categories."
  @spec categories() :: [atom()]
  def categories, do: @categories

  @doc "The broadcast statuses."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "Whether the broadcast is still editable."
  @spec editable?(t()) :: boolean()
  def editable?(%__MODULE__{status: status}), do: status in [:draft, :scheduled]

  @doc false
  def changeset(broadcast, attrs) do
    broadcast
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :subject,
      :body_markdown,
      :category,
      :segment,
      :created_by
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :subject, :body_markdown, :category])
    |> Ecto.Changeset.validate_length(:subject, min: 1, max: 200)
    |> Ecto.Changeset.validate_length(:body_markdown, min: 1, max: 200_000)
    |> validate_segment()
    |> validate_operational_segment()
  end

  @doc false
  def status_changeset(broadcast, attrs) do
    broadcast
    |> Ecto.Changeset.cast(attrs, [
      :status,
      :scheduled_for,
      :sent_at,
      :recipient_count,
      :stats
    ])
    |> Ecto.Changeset.validate_inclusion(:status, @statuses)
  end

  defp validate_segment(changeset) do
    case Ecto.Changeset.get_change(changeset, :segment) do
      nil ->
        changeset

      raw ->
        case Segment.validate(raw) do
          {:ok, canonical} ->
            Ecto.Changeset.put_change(changeset, :segment, canonical)

          {:error, {:invalid_segment, reason}} ->
            Ecto.Changeset.add_error(changeset, :segment, reason)
        end
    end
  end

  defp validate_operational_segment(changeset) do
    if Ecto.Changeset.get_field(changeset, :category) == :operational and
         not Segment.operational_booking_based?(Ecto.Changeset.get_field(changeset, :segment)) do
      Ecto.Changeset.add_error(
        changeset,
        :segment,
        "operational broadcasts require a booking-based segment"
      )
    else
      changeset
    end
  end
end
