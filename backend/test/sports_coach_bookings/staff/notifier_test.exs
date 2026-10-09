defmodule SportsCoachBookings.Staff.NotifierTest do
  @moduledoc """
  Staff flows (signup confirmation, password reset) run on the platform host with
  no tenant in context. They used to hit `{:error, :no_tenant}` from the email
  engine and the callers ignored it, so those emails were never sent.
  """

  use SportsCoachBookings.DataCase, async: false

  import ExUnit.CaptureLog

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Staff

  setup do
    tenant = insert(:tenant, slug: "staff-mail-#{System.unique_integer([:positive])}")
    put_tenant(tenant)
    user = insert(:staff_user)
    {:ok, _} = Staff.upsert_membership(tenant.id, user.id, :owner, display_name: "Owner")
    %{tenant: tenant, user: user}
  end

  defp deliveries(tenant, email) do
    TenantContext.with_tenant(tenant, fn ->
      %{data: data} = Notifications.deliveries_for_emails([email], %{})
      data
    end)
  end

  test "a password reset is delivered under the staff user's tenant when none is in context", %{
    tenant: tenant,
    user: user
  } do
    TenantContext.clear()

    assert :ok = Staff.deliver_reset_password_instructions(user.email)

    assert [delivery] = deliveries(tenant, user.email)
    assert delivery.message.template_key == "staff_reset_password"
  end

  test "a confirmation email is delivered the same way", %{tenant: tenant, user: user} do
    TenantContext.clear()

    assert :ok = Staff.deliver_confirmation_instructions(user)

    assert [delivery] = deliveries(tenant, user.email)
    assert delivery.message.template_key == "staff_confirm"
  end

  test "a staff user with no membership has nothing to send under" do
    TenantContext.clear()
    lonely = insert(:staff_user)

    log =
      capture_log(fn ->
        assert {:error, :no_tenant} =
                 Staff.Notifier.deliver_confirmation_instructions(lonely, "token")
      end)

    assert log =~ "not sent to #{lonely.email}"
  end
end
