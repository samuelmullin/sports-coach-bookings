defmodule SportsCoachBookings.Policies.Rules.OutcomeRule do
  @moduledoc """
  The credit/refund outcome for no-show and provider-cancelled situations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :credit_outcome, Ecto.Enum, values: [:return, :forfeit]
    field :money_refund_pct, :integer
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:credit_outcome, :money_refund_pct])
    |> validate_required([:credit_outcome, :money_refund_pct])
    |> validate_inclusion(:credit_outcome, [:return, :forfeit])
    |> validate_number(:money_refund_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
