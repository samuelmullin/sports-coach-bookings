defmodule SportsCoachBookings.Staff.Notifier do
  @moduledoc """
  Seam for staff transactional email: the single place Staff calls
  `SportsCoachBookings.Notifications.deliver/3`. See
  `docs/rfcs/20260928-notifications-staff-seam.md`.

  Staff accounts are platform-wide and several staff flows (signup confirmation,
  password reset) run on the platform host, where no tenant is resolved. The
  email engine is tenant-owned (messages, branding, suppressions), so when no
  tenant is in context the message is sent under the staff user's own active
  membership tenant. A staff user with no membership has no tenant to send
  under: that returns `{:error, :no_tenant}` and logs a warning.
  """

  require Logger

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Staff.StaffUser

  @doc "Sends the `staff_invite` template via Notifications."
  @spec deliver_staff_invite(struct(), binary(), struct() | nil) ::
          {:ok, term()} | {:error, term()}
  def deliver_staff_invite(invite, token, tenant) do
    # Invitations are always issued inside a tenant, so the context is set.
    Notifications.deliver(
      :staff_invite,
      %{
        email: invite.email,
        role: to_string(invite.role),
        token: token,
        tenant: tenant && tenant.name
      },
      []
    )
  end

  @doc "Sends a confirmation link via Notifications."
  @spec deliver_confirmation_instructions(StaffUser.t(), binary()) ::
          {:ok, term()} | {:error, term()}
  def deliver_confirmation_instructions(%StaffUser{} = user, token) do
    deliver(:staff_confirm, %{email: user.email, token: token}, user)
  end

  @doc "Sends a password-reset link via Notifications."
  @spec deliver_reset_password_instructions(StaffUser.t(), binary()) ::
          {:ok, term()} | {:error, term()}
  def deliver_reset_password_instructions(%StaffUser{} = user, token) do
    deliver(:staff_reset_password, %{email: user.email, token: token}, user)
  end

  defp deliver(template, assigns, %StaffUser{} = user) do
    case TenantContext.get_tenant_id() do
      nil -> deliver_under_membership(template, assigns, user)
      _tenant_id -> Notifications.deliver(template, assigns, [])
    end
  end

  defp deliver_under_membership(template, assigns, %StaffUser{} = user) do
    # `list_memberships/1` is the platform-host-safe read (self-read RLS policy);
    # the tenant-scoped `get_active_membership/1` requires a tenant already.
    case Staff.list_memberships(user) do
      [%{tenant_id: tenant_id} | _] ->
        TenantContext.with_tenant(tenant_id, fn ->
          Notifications.deliver(template, assigns, [])
        end)

      _ ->
        Logger.warning(
          "[staff_notifier] #{template} not sent to #{user.email}: no tenant in context and " <>
            "no active membership to send under"
        )

        {:error, :no_tenant}
    end
  end
end
