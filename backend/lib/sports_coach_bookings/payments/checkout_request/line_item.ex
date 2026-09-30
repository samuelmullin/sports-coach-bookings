defmodule SportsCoachBookings.Payments.CheckoutRequest.LineItem do
  @moduledoc "A single line in a hosted-checkout request."

  @enforce_keys [:name, :unit_amount, :quantity]
  defstruct [:name, :unit_amount, :quantity, :taxable, :metadata]

  @type t :: %__MODULE__{
          name: String.t(),
          unit_amount: integer(),
          quantity: pos_integer(),
          taxable: boolean() | nil,
          metadata: map() | nil
        }
end
