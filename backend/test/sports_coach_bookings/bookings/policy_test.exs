defmodule SportsCoachBookings.Bookings.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Bookings.Policy
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor

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

  test "a coach may read and mark attendance but not book or cancel" do
    coach = staff(:coach)

    for action <- Policy.coach_actions(),
        resource <- Policy.resources() do
      assert :ok = Policy.authorize(coach, action, resource)
    end

    for action <- [:book, :cancel, :rebook, :book_on_behalf, :override_cancel],
        resource <- Policy.resources() do
      assert {:error, :forbidden} = Policy.authorize(coach, action, resource)
    end
  end

  test "a household manager may book and cancel their own household's bookings" do
    manager = customer()

    for action <- Policy.customer_actions(),
        resource <- Policy.resources() do
      assert :ok = Policy.authorize(manager, action, resource)
    end

    for action <- [:book_on_behalf, :override_cancel, :mark_attendance, :roster, :history],
        resource <- Policy.resources() do
      assert {:error, :forbidden} = Policy.authorize(manager, action, resource)
    end
  end

  test "anonymous callers are denied" do
    for action <- Policy.actions(),
        resource <- Policy.resources() do
      assert {:error, :forbidden} = Policy.authorize(nil, action, resource)
    end
  end
end
