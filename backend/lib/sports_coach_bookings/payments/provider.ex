defmodule SportsCoachBookings.Payments.Provider do
  @moduledoc """
  Behaviour implemented by each payment provider (Stripe first, behind this
  interface).

  All money is passed as `SportsCoachBookings.Core.Money` (integer minor units).
  Providers never see Ecto structs with tenant data beyond what they need; the
  `account_ref` is opaque to callers.
  """

  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Payments.{CheckoutRequest, CheckoutSession, NormalizedEvent}

  @type account_ref :: String.t()
  @type payment_ref :: String.t()
  @type refund_ref :: String.t()

  @typedoc """
  The provider's view of a connected account's readiness:

    * `:charges_enabled` — the account may accept charges
    * `:payouts_enabled` — the account may receive payouts
    * `:requirements_due` — outstanding verification requirements
  """
  @type account_status :: %{
          charges_enabled: boolean(),
          payouts_enabled: boolean(),
          requirements_due: [String.t()] | map()
        }

  @callback create_connected_account(tenant :: term()) ::
              {:ok, account_ref()} | {:error, term()}

  @callback onboarding_link(account_ref(), return_url :: String.t(), refresh_url :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback account_status(account_ref()) :: {:ok, account_status()} | {:error, term()}

  @callback create_checkout(account_ref(), CheckoutRequest.t()) ::
              {:ok, CheckoutSession.t()} | {:error, term()}

  @callback refund(account_ref(), payment_ref(), Money.t(), reason :: term()) ::
              {:ok, refund_ref()} | {:error, term()}

  @callback verify_webhook(raw_body :: binary(), headers :: list() | map()) ::
              {:ok, term()} | {:error, :invalid_signature}

  @callback normalize_event(event :: term()) :: {:ok, NormalizedEvent.t()} | :ignore
end
