defmodule SportsCoachBookings.Catalog.TaxRate do
  @moduledoc "A tenant tax rate (name + basis points). One active rate in the MVP."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "tax_rates" do
    field :tenant_id, :binary_id
    field :name, :string
    field :rate_bps, :integer
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(tax_rate, attrs) do
    tax_rate
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :name, :rate_bps, :active])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :rate_bps])
    |> Ecto.Changeset.validate_number(:rate_bps,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10_000
    )
    |> Ecto.Changeset.unique_constraint(:active, name: :tax_rates_one_active_per_tenant)
  end
end
