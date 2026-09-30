defmodule SportsCoachBookings.Inventory.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Inventory.Policy

  @tenant Ecto.UUID.generate()

  defp staff(role) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: @tenant, role: role)
  end

  defp customer do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: Ecto.UUID.generate(),
      tenant_id: @tenant
    )
  end

  test "owner and admin may do everything" do
    for role <- [:owner, :admin],
        action <- Policy.actions(),
        resource <- Policy.resources() do
      assert :ok = Policy.authorize(staff(role), action, resource),
             "expected #{role} to #{action} on #{resource}"
    end
  end

  test "a coach is read-only plus pickup operations" do
    coach = staff(:coach)

    for action <- Policy.coach_actions(),
        resource <- Policy.resources() do
      assert :ok = Policy.authorize(coach, action, resource),
             "expected coach to #{action} #{resource}"
    end

    for action <- Policy.actions() -- Policy.coach_actions() do
      assert {:error, :forbidden} = Policy.authorize(coach, action, :product)
      assert {:error, :forbidden} = Policy.authorize(coach, action, :stock_level)
    end
  end

  test "a household manager can browse the shop and view own pickups" do
    manager = customer()

    assert :ok = Policy.authorize(manager, :list_public, :product)
    assert :ok = Policy.authorize(manager, :view_public, :product)
    assert :ok = Policy.authorize(manager, :view_pickup_status, :fulfillment)

    assert {:error, :forbidden} = Policy.authorize(manager, :create, :product)
    assert {:error, :forbidden} = Policy.authorize(manager, :receive_stock, :stock_level)
  end

  test "anonymous callers can browse the shop but nothing else" do
    assert :ok = Policy.authorize(nil, :list_public, :product)
    assert :ok = Policy.authorize(nil, :view_public, :product)

    assert {:error, :forbidden} = Policy.authorize(nil, :list, :product)
    assert {:error, :forbidden} = Policy.authorize(nil, :view_pickup_status, :fulfillment)
    assert {:error, :forbidden} = Policy.authorize(nil, :create, :product)
  end
end
