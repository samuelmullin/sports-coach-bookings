defmodule SportsCoachBookings.Notifications.Broadcasts.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast
  alias SportsCoachBookings.Notifications.Broadcasts.Policy

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

  defp broadcast(tenant_id) do
    %Broadcast{id: Ecto.UUID.generate(), tenant_id: tenant_id}
  end

  test "owners and admins may manage broadcasts in their tenant" do
    for role <- [:owner, :admin], action <- Policy.actions() do
      assert :ok = Policy.authorize(staff(role), action, :broadcasts)
      assert :ok = Policy.authorize(staff(role), action, broadcast(@tenant_id))
    end
  end

  test "staff cannot touch another tenant's broadcast" do
    assert {:error, :forbidden} =
             Policy.authorize(staff(:admin), :send, broadcast(@other_tenant))
  end

  test "coaches, customers, and anonymous are denied" do
    for actor <- [staff(:coach), customer(), nil], action <- Policy.actions() do
      assert {:error, :forbidden} = Policy.authorize(actor, action, :broadcasts)
      assert {:error, :forbidden} = Policy.authorize(actor, action, broadcast(@tenant_id))
    end
  end

  test "unknown actions are denied by default" do
    assert {:error, :forbidden} =
             Policy.authorize(staff(:owner), :delete_everything, :broadcasts)
  end
end
