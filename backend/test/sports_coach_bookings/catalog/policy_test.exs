defmodule SportsCoachBookings.Catalog.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Catalog.Policy
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor

  @staff_actions %{
    venue: [:list, :get, :create, :update, :archive],
    offering: [:list, :get, :create, :update, :archive, :reorder],
    package: [:list, :get, :create, :update, :archive, :reorder],
    discount: [:list, :get, :create, :update, :archive, :validate_discount],
    tax_rate: [:list, :get, :create, :update, :archive]
  }

  @portal_resources [:venue, :offering, :package]

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

  test "owner and admin may perform every staff action" do
    for role <- [:owner, :admin], {resource, actions} <- @staff_actions, action <- actions do
      assert :ok = Policy.authorize(staff(role), action, resource),
             "expected #{role} to #{action} #{resource}"
    end
  end

  test "coaches may only read venues and offerings" do
    coach = staff(:coach)

    assert :ok = Policy.authorize(coach, :list, :venue)
    assert :ok = Policy.authorize(coach, :get, :offering)

    for resource <- [:package, :discount, :tax_rate] do
      assert {:error, :forbidden} = Policy.authorize(coach, :list, resource)
      assert {:error, :forbidden} = Policy.authorize(coach, :get, resource)
    end

    for action <- [:create, :update, :archive, :reorder] do
      assert {:error, :forbidden} = Policy.authorize(coach, action, :venue)
      assert {:error, :forbidden} = Policy.authorize(coach, action, :offering)
    end
  end

  test "customers and anonymous callers are denied every staff action" do
    for actor <- [customer(), nil], {resource, actions} <- @staff_actions, action <- actions do
      assert {:error, :forbidden} = Policy.authorize(actor, action, resource),
             "expected #{inspect(actor)} to be denied #{action} #{resource}"
    end
  end

  test "portal listing is open to every actor" do
    for actor <- [staff(:owner), staff(:coach), customer(), nil], resource <- @portal_resources do
      assert :ok = Policy.authorize(actor, :list_public, resource)
    end
  end

  test "unknown resources are denied for non-managers" do
    assert {:error, :forbidden} = Policy.authorize(staff(:coach), :list, :unknown)
    assert {:error, :forbidden} = Policy.authorize(nil, :list, :unknown)
  end
end
