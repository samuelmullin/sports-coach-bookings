defmodule SportsCoachBookings.Policies.Outcome do
  @moduledoc """
  The result of evaluating a cancellation/rebooking policy snapshot.

    * `allowed?` — whether the action is permitted at all (only rebooking can be
      denied by policy; cancelling and recording a no-show are always allowed).
    * `reason` — an atom explaining a denial, or `nil`.
    * `credit_outcome` — `:return | :forfeit | nil` (nil for rebooking).
    * `refund_amount` — a `Money.t()` to refund, or `nil` when no money moves
      (credit-based bookings, or rebooking).
    * `tier_matched` — the zero-based index of the matched cancellation tier, or
      `nil` for no-show / provider-cancel / rebook.
  """

  defstruct allowed?: false,
            reason: nil,
            credit_outcome: nil,
            refund_amount: nil,
            tier_matched: nil

  @type credit_outcome :: :return | :forfeit | nil

  @type t :: %__MODULE__{
          allowed?: boolean(),
          reason: atom() | nil,
          credit_outcome: credit_outcome(),
          refund_amount: SportsCoachBookings.Core.Money.t() | nil,
          tier_matched: non_neg_integer() | nil
        }
end
