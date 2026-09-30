defmodule SportsCoachBookings.Payments.ProviderAccount do
  @moduledoc """
  The tenant's connected payment-provider account (Stripe Connect Express).

  Tenant-owned (RLS). One row per `(tenant, provider)`. The `platform_fee_bps`
  is platform-controlled; tenants cannot edit it (see `Payments.Policy`).
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @statuses ["not_connected", "pending", "restricted", "enabled"]

  schema "provider_accounts" do
    field :tenant_id, :binary_id
    field :provider, :string
    field :account_ref, :string
    field :status, :string
    field :charges_enabled, :boolean, default: false
    field :payouts_enabled, :boolean, default: false
    field :requirements, :map, default: %{}
    field :platform_fee_bps, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(account, attrs) do
    account
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :provider,
      :account_ref,
      :status,
      :charges_enabled,
      :payouts_enabled,
      :requirements,
      :platform_fee_bps
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :provider, :account_ref])
    |> Ecto.Changeset.validate_number(:platform_fee_bps, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :provider])
  end

  @doc "True when the account can accept charges (checkout is allowed)."
  @spec charges_enabled?(t()) :: boolean()
  def charges_enabled?(%__MODULE__{charges_enabled: enabled}), do: enabled == true

  @doc "The statuses an account row may hold."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses
end
