defmodule SportsCoachBookings.Payments.CheckoutSession do
  @moduledoc "The result of creating a hosted checkout session."

  @enforce_keys [:session_ref, :redirect_url]
  defstruct [:session_ref, :redirect_url, :expires_at]

  @type t :: %__MODULE__{
          session_ref: String.t(),
          redirect_url: String.t(),
          expires_at: DateTime.t() | nil
        }
end
