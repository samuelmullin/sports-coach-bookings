defmodule SportsCoachBookings.Notifications.Message do
  @moduledoc """
  One outbound message per `SportsCoachBookings.Notifications.deliver/4` call.
  Tenant-owned (RLS).
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Notifications.Delivery

  @type t :: %__MODULE__{}

  @categories [:transactional, :operational, :marketing]

  schema "messages" do
    field :tenant_id, :binary_id
    field :template_key, :string
    field :category, Ecto.Enum, values: @categories, default: :transactional
    field :subject, :string
    field :idempotency_key, :string
    field :assigns, :map, default: %{}

    has_many :deliveries, Delivery, foreign_key: :message_id

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :template_key,
      :category,
      :subject,
      :idempotency_key,
      :assigns
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :template_key, :category])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :idempotency_key])
  end

  @doc "The allowed message categories."
  @spec categories() :: [atom()]
  def categories, do: @categories
end
