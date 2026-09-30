defmodule SportsCoachBookings.Payments.NormalizedEvent do
  @moduledoc """
  A provider-agnostic webhook event, produced by `Provider.normalize_event/1`.

  `type` is one of the normalised types the Payments context understands:

    * `:checkout_completed`
    * `:checkout_expired`
    * `:payment_failed`
    * `:charge_refunded`
    * `:account_updated`

  `data` is a flat, JSON-serialisable map. Providers populate the keys they can;
  missing keys are `nil`. The canonical keys are:

      %{
        "tenant_id" => binary | nil,        # resolved by the provider from metadata
        "order_id" => binary | nil,
        "order_number" => String.t() | nil,
        "account_ref" => binary | nil,      # connected account id
        "checkout_ref" => binary | nil,     # checkout session id
        "payment_ref" => binary | nil,      # payment intent id
        "amount" => integer | nil,          # minor units
        "currency" => String.t() | nil,
        "refund_ref" => binary | nil,
        "refund_amount" => integer | nil,
        "charges_enabled" => boolean | nil,
        "payouts_enabled" => boolean | nil,
        "requirements" => map | nil
      }
  """

  @enforce_keys [:type, :event_id]
  defstruct [:type, :event_id, :data]

  @type t :: %__MODULE__{type: atom(), event_id: String.t(), data: map()}
end
