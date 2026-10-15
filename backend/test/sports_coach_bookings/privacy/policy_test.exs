defmodule SportsCoachBookings.Privacy.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Privacy.Policy

  @tenant_id "11111111-1111-7111-8111-111111111111"

  defp staff(role),
    do: StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: @tenant_id, role: role)

  defp customer,
    do:
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: Ecto.UUID.generate(),
        tenant_id: @tenant_id
      )

  test "a household manager may export and erase their household" do
    for action <- Policy.actions(),
        do: assert(:ok = Policy.authorize(customer(), action, :household))
  end

  test "owner, admin, coach, and anonymous are denied" do
    for actor <- [staff(:owner), staff(:admin), staff(:coach), nil],
        action <- Policy.actions() do
      assert {:error, :forbidden} = Policy.authorize(actor, action, :household)
    end
  end

  test "unknown actions and resources are denied" do
    assert {:error, :forbidden} = Policy.authorize(customer(), :delete_everything, :household)
    assert {:error, :forbidden} = Policy.authorize(customer(), :export, :tenant)
  end
end
