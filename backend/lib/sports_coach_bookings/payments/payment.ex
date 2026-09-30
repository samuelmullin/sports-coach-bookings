defmodule SportsCoachBookings.Payments.Payment do
  @moduledoc """
  A hosted-checkout payment attempt. Tenant-owned (RLS).

  `order_id` is a cross-context reference to Commerce (uuid only). `payment_ref`
  is the provider payment/intent id; `(provider, payment_ref)` is unique so a
  webhook can be matched idempotently.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @statuses [:pending, :succeeded, :failed, :expired]

  schema "payments" do
    field :tenant_id, :binary_id
    field :provider, :string
    field :order_id, :binary_id
    field :checkout_ref, :string
    field :payment_ref, :string
    field :amount, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :raw, :map, default: %{}

    timestamps()
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :provider,
      :order_id,
      :checkout_ref,
      :payment_ref,
      :amount,
      :status,
      :raw
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :provider, :amount, :status])
    |> Ecto.Changeset.unique_constraint([:provider, :payment_ref])
  end

  @doc "The statuses a payment can be in."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses
end
