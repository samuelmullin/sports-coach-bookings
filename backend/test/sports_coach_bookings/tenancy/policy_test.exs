defmodule SportsCoachBookings.Tenancy.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Tenancy.Policy

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

  test "owners and admins may read and update settings" do
    for role <- [:owner, :admin], action <- [:get, :update] do
      assert :ok = Policy.authorize(staff(role), action, :settings)
    end
  end

  test "coaches, customers, and anonymous callers may not touch settings" do
    for actor <- [staff(:coach), customer(), nil], action <- [:get, :update] do
      assert {:error, :forbidden} = Policy.authorize(actor, action, :settings)
    end
  end

  test "all staff may read branding; only owner/admin may update or upload" do
    for role <- [:owner, :admin, :coach] do
      assert :ok = Policy.authorize(staff(role), :get, :branding)
    end

    for role <- [:owner, :admin], action <- [:update, :upload] do
      assert :ok = Policy.authorize(staff(role), action, :branding)
    end

    for action <- [:update, :upload] do
      assert {:error, :forbidden} = Policy.authorize(staff(:coach), action, :branding)
      assert {:error, :forbidden} = Policy.authorize(customer(), action, :branding)
      assert {:error, :forbidden} = Policy.authorize(nil, action, :branding)
    end
  end

  test "only the owner may transfer ownership or delete the tenant" do
    assert :ok = Policy.authorize(staff(:owner), :transfer_ownership, :tenant)
    assert :ok = Policy.authorize(staff(:owner), :delete, :tenant)

    for actor <- [staff(:admin), staff(:coach), customer(), nil] do
      assert {:error, :forbidden} = Policy.authorize(actor, :transfer_ownership, :tenant)
      assert {:error, :forbidden} = Policy.authorize(actor, :delete, :tenant)
    end
  end

  test "signup, slug checks, and public branding are open" do
    for actor <- [staff(:owner), customer(), nil] do
      assert :ok = Policy.authorize(actor, :signup, :tenant)
      assert :ok = Policy.authorize(actor, :view, :slug)
      assert :ok = Policy.authorize(actor, :view, :public_branding)
    end
  end
end
