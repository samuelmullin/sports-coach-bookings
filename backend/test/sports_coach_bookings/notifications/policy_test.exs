defmodule SportsCoachBookings.Notifications.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.Policy

  @tenant_id "11111111-1111-7111-8111-111111111111"
  @other_tenant "22222222-2222-7222-8222-222222222222"

  defp staff(role, tenant_id \\ @tenant_id) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant_id, role: role)
  end

  defp customer(tenant_id \\ @tenant_id) do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: Ecto.UUID.generate(),
      tenant_id: tenant_id
    )
  end

  defp delivery(tenant_id) do
    %Delivery{id: Ecto.UUID.generate(), tenant_id: tenant_id}
  end

  describe "delivery log and resend" do
    test "owners and admins may view the log and resend within their tenant" do
      for role <- [:owner, :admin], action <- [:view_delivery_log, :resend_delivery] do
        assert :ok = Policy.authorize(staff(role), action, :notifications)
        assert :ok = Policy.authorize(staff(role), action, delivery(@tenant_id))
      end
    end

    test "staff cannot touch another tenant's delivery" do
      assert {:error, :forbidden} =
               Policy.authorize(staff(:admin), :resend_delivery, delivery(@other_tenant))

      assert {:error, :forbidden} =
               Policy.authorize(staff(:admin), :view_delivery_log, delivery(@other_tenant))
    end

    test "coaches, customers, and anonymous are denied admin actions" do
      for actor <- [staff(:coach), customer(), nil],
          action <- [:view_delivery_log, :resend_delivery] do
        assert {:error, :forbidden} = Policy.authorize(actor, action, :notifications)
        assert {:error, :forbidden} = Policy.authorize(actor, action, delivery(@tenant_id))
      end
    end
  end

  describe "own preferences" do
    test "any authenticated actor manages their own preferences" do
      for actor <- [staff(:owner), staff(:admin), staff(:coach), customer()],
          action <- [:view_preferences, :update_preferences] do
        assert :ok = Policy.authorize(actor, action, :preferences)
      end
    end

    test "anonymous cannot manage preferences" do
      assert {:error, :forbidden} = Policy.authorize(nil, :view_preferences, :preferences)
      assert {:error, :forbidden} = Policy.authorize(nil, :update_preferences, :preferences)
    end
  end

  test "the unknown actions are denied by default" do
    assert {:error, :forbidden} =
             Policy.authorize(staff(:owner), :delete_everything, :notifications)
  end
end
