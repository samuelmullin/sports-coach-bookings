defmodule SportsCoachBookings.Policies.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Policies.CancellationPolicy
  alias SportsCoachBookings.Policies.Policy

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

  defp policy_struct do
    struct!(%CancellationPolicy{id: Ecto.UUID.generate(), tenant_id: @tenant})
  end

  @write_actions [:create, :update, :archive, :set_default, :assign, :unassign]
  @read_actions [:list, :get, :simulate]

  test "owner and admin may do everything on every resource" do
    resources = [:cancellation_policy, :offering_policy_assignment, policy_struct()]

    for role <- [:owner, :admin],
        action <- Policy.actions() -- [:summary],
        resource <- resources do
      assert :ok = Policy.authorize(staff(role), action, resource),
             "expected #{role} to #{action} on #{inspect(resource)}"
    end
  end

  test "a coach has read-only access to policies" do
    for action <- @read_actions do
      assert :ok = Policy.authorize(staff(:coach), action, :cancellation_policy)
    end

    for action <- @write_actions ++ [:summary] do
      assert {:error, :forbidden} =
               Policy.authorize(staff(:coach), action, :cancellation_policy)
    end
  end

  test "any caller may read the portal policy summary" do
    for actor <- [nil, staff(:coach), staff(:owner), customer()] do
      assert :ok = Policy.authorize(actor, :summary, :offering_policy)
    end
  end

  test "staff from another tenant cannot act on a policy" do
    foreign = staff(:admin, Ecto.UUID.generate())
    assert {:error, :forbidden} = Policy.authorize(foreign, :update, policy_struct())
  end

  test "anonymous and customer callers are denied staff actions" do
    for actor <- [nil, customer()],
        action <- @write_actions ++ @read_actions,
        resource <- [:cancellation_policy, :offering_policy_assignment] do
      assert {:error, :forbidden} = Policy.authorize(actor, action, resource)
    end
  end
end
