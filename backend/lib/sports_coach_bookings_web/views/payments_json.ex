defmodule SportsCoachBookingsWeb.PaymentsJSON do
  @moduledoc "Serialises payment provider connection state for the staff API."

  @doc "Serialises a `Payments.connect_status/0` map."
  @spec connect_status(map()) :: map()
  def connect_status(status) when is_map(status) do
    %{
      provider: status.provider,
      account_ref: status.account_ref,
      status: status.status,
      charges_enabled: status.charges_enabled,
      payouts_enabled: status.payouts_enabled,
      requirements: status.requirements,
      platform_fee_bps: status.platform_fee_bps
    }
  end
end
