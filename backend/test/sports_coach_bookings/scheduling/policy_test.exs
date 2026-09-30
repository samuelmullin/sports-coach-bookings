defmodule SportsCoachBookings.Scheduling.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Scheduling.Policy

  @tenant Ecto.UUID.generate()

  defp staff(role, tenant \\ @tenant) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant, role: role)
  end

  defp customer do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: Ecto.UUID.generate(),
      tenant_id: @tenant
    )
  end

  @manage [:list, :get, :create, :create_series, :update, :cancel, :reschedule, :edit_series]
  @read [:list, :get, :my_sessions]
  @portal [:list_public, :get_public]
  @staff_resources [:session, :session_series, :calendar]

  test "owner and admin may manage scheduling resources" do
    for role <- [:owner, :admin],
        action <- @manage,
        resource <- @staff_resources do
      assert :ok = Policy.authorize(staff(role), action, resource),
             "expected #{role} to #{action} on #{resource}"
    end
  end

  test "a coach may read sessions but not manage them" do
    for action <- @read, resource <- @staff_resources do
      assert :ok = Policy.authorize(staff(:coach), action, resource)
    end

    for action <- @manage -- @read, resource <- @staff_resources do
      assert {:error, :forbidden} = Policy.authorize(staff(:coach), action, resource)
    end
  end

  test "anonymous and customers may read the portal calendar" do
    for actor <- [nil, customer()],
        action <- @portal,
        resource <- [:session, :calendar] do
      assert :ok = Policy.authorize(actor, action, resource)
    end
  end

  test "anonymous and customers are denied staff scheduling actions" do
    for actor <- [nil, customer()],
        action <- @manage,
        resource <- @staff_resources do
      assert {:error, :forbidden} = Policy.authorize(actor, action, resource)
    end
  end

  test "actions/0 covers the full matrix" do
    assert Enum.sort(Policy.actions()) == Enum.sort(Enum.uniq(@manage ++ @read ++ @portal))
  end
end
