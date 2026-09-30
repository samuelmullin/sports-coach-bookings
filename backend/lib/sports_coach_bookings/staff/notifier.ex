defmodule SportsCoachBookings.Staff.Notifier do
  @moduledoc """
  Seam for staff transactional email.

  WP-05 (`SportsCoachBookings.Notifications`) owns the email engine and is not
  merged. Until it lands, this module is the single place that would call
  `Notifications.deliver/…`; it no-ops (logging in dev) and returns
  `{:ok, :stubbed}`. See `docs/rfcs/20260928-notifications-staff-seam.md`.
  """

  require Logger

  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Staff.StaffUser

  @doc "Sends the `staff_invite` template via Notifications when available."
  @spec deliver_staff_invite(struct(), binary(), struct() | nil) :: {:ok, term()}
  def deliver_staff_invite(invite, token, tenant) do
    deliver(:staff_invite, %{
      email: invite.email,
      role: to_string(invite.role),
      token: token,
      tenant: tenant && tenant.name
    })
  end

  @doc "Sends a confirmation link when Notifications is available."
  @spec deliver_confirmation_instructions(StaffUser.t(), binary()) :: {:ok, term()}
  def deliver_confirmation_instructions(%StaffUser{} = user, token) do
    deliver(:staff_confirm, %{email: user.email, token: token})
  end

  @doc "Sends a password-reset link when Notifications is available."
  @spec deliver_reset_password_instructions(StaffUser.t(), binary()) :: {:ok, term()}
  def deliver_reset_password_instructions(%StaffUser{} = user, token) do
    deliver(:staff_reset_password, %{email: user.email, token: token})
  end

  defp deliver(template, assigns) do
    if Code.ensure_loaded?(Notifications) and function_exported?(Notifications, :deliver, 3) do
      # The function is optional (wp-05); apply/3 keeps this compiling when it is
      # absent. Remove once Notifications.deliver/3 always exists.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Notifications, :deliver, [template, assigns, []])
    else
      Logger.info(
        "[staff_notifier] #{template} stub for #{assigns[:email]} " <>
          "(WP-05 Notifications not merged)"
      )

      {:ok, :stubbed}
    end
  end
end
