defmodule SportsCoachBookings.Customers.Notifier do
  @moduledoc """
  Seam for customer transactional email: the single place Customers calls
  `SportsCoachBookings.Notifications.deliver/3`, which owns templates, branding,
  suppression, and delivery. See `docs/rfcs/20260928-customers-notifications-seam.md`.
  """

  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.HouseholdInvite
  alias SportsCoachBookings.Notifications

  @doc "Sends the account-confirmation link."
  @spec deliver_confirmation_instructions(CustomerUser.t(), binary()) ::
          {:ok, term()} | {:error, term()}
  def deliver_confirmation_instructions(%CustomerUser{} = user, token) do
    deliver(:customer_confirm, %{email: user.email, token: token})
  end

  @doc "Sends a password-reset link."
  @spec deliver_reset_password_instructions(CustomerUser.t(), binary()) ::
          {:ok, term()} | {:error, term()}
  def deliver_reset_password_instructions(%CustomerUser{} = user, token) do
    deliver(:customer_reset_password, %{email: user.email, token: token})
  end

  @doc "Sends the confirm-your-new-address link for an email change."
  @spec deliver_email_change_instructions(CustomerUser.t(), binary(), binary()) ::
          {:ok, term()} | {:error, term()}
  def deliver_email_change_instructions(%CustomerUser{} = user, new_email, token) do
    deliver(:customer_email_change, %{email: new_email, previous_email: user.email, token: token})
  end

  @doc "Sends a household co-manager invitation."
  @spec deliver_household_invite(HouseholdInvite.t(), binary(), struct() | nil) ::
          {:ok, term()} | {:error, term()}
  def deliver_household_invite(%HouseholdInvite{} = invite, token, tenant) do
    deliver(:household_invite, %{
      email: invite.email,
      relationship: invite.relationship,
      token: token,
      tenant: tenant && tenant.name
    })
  end

  defp deliver(template, assigns), do: Notifications.deliver(template, assigns, [])
end
