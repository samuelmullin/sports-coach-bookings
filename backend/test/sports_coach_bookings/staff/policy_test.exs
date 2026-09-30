defmodule SportsCoachBookings.Staff.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Staff.Policy

  defp staff(role) do
    StaffActor.new(
      staff_user_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      role: role
    )
  end

  defp customer do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate()
    )
  end

  test "owners may manage any team action and transfer ownership" do
    owner = staff(:owner)

    assert :ok = Policy.authorize(owner, :list, :team)
    assert :ok = Policy.authorize(owner, {:invite, :owner}, :team)
    assert :ok = Policy.authorize(owner, {:invite, :admin}, :team)
    assert :ok = Policy.authorize(owner, {:invite, :coach}, :team)
    assert :ok = Policy.authorize(owner, {:change_role, :admin}, :team)
    assert :ok = Policy.authorize(owner, {:remove, :admin}, :team)
    assert :ok = Policy.authorize(owner, :transfer_ownership, :tenant)
  end

  test "admins manage admins and coaches but never owners" do
    admin = staff(:admin)

    assert :ok = Policy.authorize(admin, :list, :team)
    assert :ok = Policy.authorize(admin, {:invite, :admin}, :team)
    assert :ok = Policy.authorize(admin, {:invite, :coach}, :team)

    assert {:error, :forbidden} = Policy.authorize(admin, {:invite, :owner}, :team)
    assert {:error, :forbidden} = Policy.authorize(admin, {:change_role, :owner}, :team)
    assert {:error, :forbidden} = Policy.authorize(admin, {:remove, :owner}, :team)
    assert {:error, :forbidden} = Policy.authorize(admin, :transfer_ownership, :tenant)
  end

  test "coaches, customers, and anonymous callers are denied team management" do
    actors = [staff(:coach), customer(), nil]

    actions = [
      {:list, :team},
      {{:invite, :coach}, :team},
      {{:change_role, :coach}, :team},
      {{:remove, :coach}, :team},
      {:transfer_ownership, :tenant}
    ]

    for actor <- actors, {action, resource} <- actions do
      assert {:error, :forbidden} = Policy.authorize(actor, action, resource)
    end
  end

  test "any authenticated staff actor may call /me" do
    for role <- [:owner, :admin, :coach] do
      assert :ok = Policy.authorize(staff(role), :me, :staff_user)
    end

    assert {:error, :forbidden} = Policy.authorize(nil, :me, :staff_user)
    assert {:error, :forbidden} = Policy.authorize(customer(), :me, :staff_user)
  end
end
