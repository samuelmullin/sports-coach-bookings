defmodule SportsCoachBookings.Payments.Refund do
  @moduledoc """
  A refund issued against a payment. Tenant-owned (RLS).

  `(tenant_id, refund_ref)` is unique so replaying a `charge.refunded` webhook
  cannot create a second refund row. `actor_type`/`actor_id` mirror the
  `Core.Audit` actor shape.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Payments.Payment

  @type t :: %__MODULE__{}

  @statuses [:pending, :succeeded, :failed]

  schema "refunds" do
    field :tenant_id, :binary_id
    field :amount, :integer
    field :reason, :string
    field :refund_ref, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :actor_type, :string
    field :actor_id, :binary_id

    belongs_to :payment, Payment, foreign_key: :payment_id, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(refund, attrs) do
    refund
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :payment_id,
      :amount,
      :reason,
      :refund_ref,
      :status,
      :actor_type,
      :actor_id
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :payment_id, :amount, :status])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :refund_ref])
  end

  @doc "The statuses a refund can be in."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses
end
