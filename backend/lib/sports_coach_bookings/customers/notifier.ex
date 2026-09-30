defmodule SportsCoachBookings.Customers.Notifier do
  @moduledoc """
  Seam for customer transactional email.

  WP-05 (`SportsCoachBookings.Notifications`) owns the email engine and is not
  merged. Until it lands this module is the single place that would call
  `Notifications.deliver/…`; it no-ops (logging) and returns `{:ok, :stubbed}`.
  See `docs/rfcs/20260928-customers-notifications-seam.md`.
  """

  require Logger

  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.HouseholdInvite
  alias SportsCoachBookings.Notifications

  @doc "Sends the account-confirmation link."
  @spec deliver_confirmation_instructions(CustomerUser.t(), binary()) :: {:ok, term()}
  def deliver_confirmation_instructions(%CustomerUser{} = user, token) do
    deliver(:customer_confirm, %{email: user.email, token: token})
  end

  @doc "Sends a password-reset link."
  @spec deliver_reset_password_instructions(CustomerUser.t(), binary()) :: {:ok, term()}
  def deliver_reset_password_instructions(%CustomerUser{} = user, token) do
    deliver(:customer_reset_password, %{email: user.email, token: token})
  end

  @doc "Sends the confirm-your-new-address link for an email change."
  @spec deliver_email_change_instructions(CustomerUser.t(), binary(), binary()) :: {:ok, term()}
  def deliver_email_change_instructions(%CustomerUser{} = user, new_email, token) do
    deliver(:customer_email_change, %{email: new_email, previous_email: user.email, token: token})
  end

  @doc "Sends a household co-manager invitation."
  @spec deliver_household_invite(HouseholdInvite.t(), binary(), struct() | nil) :: {:ok, term()}
  def deliver_household_invite(%HouseholdInvite{} = invite, token, tenant) do
    deliver(:household_invite, %{
      email: invite.email,
      relationship: invite.relationship,
      token: token,
      tenant: tenant && tenant.name
    })
  end

  defp deliver(template, assigns) do
    if Code.ensure_loaded?(Notifications) and function_exported?(Notifications, :deliver, 3) do
      # Optional until WP-05 lands; apply/3 keeps this compiling when absent.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Notifications, :deliver, [template, assigns, []])
    else
      Logger.info(
        "[customers_notifier] #{template} stub for #{assigns[:email]} " <>
          "(WP-05 Notifications not merged)"
      )

      {:ok, :stubbed}
    end
  end
end
