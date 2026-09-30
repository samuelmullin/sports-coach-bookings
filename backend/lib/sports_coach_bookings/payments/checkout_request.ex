defmodule SportsCoachBookings.Payments.CheckoutRequest do
  @moduledoc """
  A provider-agnostic hosted-checkout request.
  """

  alias SportsCoachBookings.Payments.CheckoutRequest.LineItem

  @enforce_keys [:order_id, :order_number, :line_items, :currency, :success_url, :cancel_url]
  defstruct [
    :order_id,
    :order_number,
    :customer_email,
    :line_items,
    :currency,
    :application_fee_amount,
    :success_url,
    :cancel_url,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          order_id: binary(),
          order_number: String.t(),
          customer_email: String.t() | nil,
          line_items: [LineItem.t()],
          currency: String.t(),
          application_fee_amount: integer() | nil,
          success_url: String.t(),
          cancel_url: String.t(),
          metadata: map()
        }
end
