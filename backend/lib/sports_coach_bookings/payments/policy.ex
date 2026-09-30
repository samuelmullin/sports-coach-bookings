defmodule SportsCoachBookings.Payments.Policy do
  @moduledoc """
  Authorization for payment settings. Owned by WP-04.

  Connecting a provider account and changing payment settings is **owner-only**
  (the brief: "payment provider settings" is an owner-only action, and the
  `platform_fee_bps` is platform-controlled, never tenant-editable). Admins,
  coaches, customers, and anonymous callers are denied.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor

  @owner_actions [:connect_status, :start_onboarding, :get, :update, :update_settings]

  @impl SportsCoachBookings.Core.Policy
  def authorize(%StaffActor{role: :owner}, action, :provider_account)
      when action in @owner_actions,
      do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}
end
