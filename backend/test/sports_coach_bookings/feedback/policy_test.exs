defmodule SportsCoachBookings.Feedback.PolicyTest do
  use ExUnit.Case, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Feedback.Policy
  alias SportsCoachBookings.Players.Player

  defmodule VisibleCoachAccess do
    @moduledoc false
    def player_visible?(_actor, _player_id), do: true
  end

  defmodule HiddenCoachAccess do
    @moduledoc false
    def player_visible?(_actor, _player_id), do: false
  end

  @tenant Ecto.UUID.generate()
  @household Ecto.UUID.generate()

  defp staff(role, tenant \\ @tenant) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant, role: role)
  end

  defp customer(household \\ @household, tenant \\ @tenant) do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: household,
      tenant_id: tenant
    )
  end

  defp player(overrides \\ %{}) do
    struct!(
      %Player{id: Ecto.UUID.generate(), tenant_id: @tenant, household_id: @household},
      overrides
    )
  end

  setup do
    previous = Application.get_env(:sports_coach_bookings, :coach_access)

    on_exit(fn ->
      Application.put_env(:sports_coach_bookings, :coach_access, previous)
    end)

    :ok
  end

  test "owners and admins may manage feedback and skill tags" do
    for role <- [:owner, :admin], action <- Policy.manager_actions() do
      assert :ok = Policy.authorize(staff(role), action, :feedback),
             "expected #{role} to #{action}"
    end

    assert :ok = Policy.authorize(staff(:owner), :manage_skill_tags, :skill_tag)
    assert :ok = Policy.authorize(staff(:admin), :list_skill_tags, :skill_tag)
  end

  test "a coach may read, submit, share, edit, and roster but not review or manage tags" do
    coach = staff(:coach)

    for action <- Policy.coach_actions() do
      assert :ok = Policy.authorize(coach, action, :feedback),
             "expected coach to #{action}"
    end

    assert :ok = Policy.authorize(coach, :list_skill_tags, :skill_tag)
    assert {:error, :forbidden} = Policy.authorize(coach, :review, :feedback)
    assert {:error, :forbidden} = Policy.authorize(coach, :manage_skill_tags, :skill_tag)
  end

  test "a coach sees a player only when CoachAccess allows it" do
    coach = staff(:coach)
    target = player(%{id: "player-1"})

    Application.put_env(:sports_coach_bookings, :coach_access, HiddenCoachAccess)
    assert {:error, :forbidden} = Policy.authorize(coach, :get, target)

    Application.put_env(:sports_coach_bookings, :coach_access, VisibleCoachAccess)
    assert :ok = Policy.authorize(coach, :get, target)
  end

  test "a household manager sees shared feedback for own players only" do
    assert :ok = Policy.authorize(customer(), :list_shared, player())

    assert {:error, :forbidden} =
             Policy.authorize(customer(Ecto.UUID.generate()), :list_shared, player())

    assert {:error, :forbidden} = Policy.authorize(customer(), :create, :feedback)
    assert {:error, :forbidden} = Policy.authorize(customer(), :list, :feedback)
  end

  test "anonymous callers are denied everything" do
    for action <- Policy.actions(), resource <- [:feedback, :skill_tag, player()] do
      assert {:error, :forbidden} = Policy.authorize(nil, action, resource)
    end
  end
end
