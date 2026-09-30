defmodule SportsCoachBookings.Players.PolicyTest do
  use ExUnit.Case, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Players.Policy

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

  defp staff(role) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: @tenant, role: role)
  end

  defp customer(household \\ @household) do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: household,
      tenant_id: @tenant
    )
  end

  defp player(overrides \\ %{}) do
    struct!(
      %Player{
        id: Ecto.UUID.generate(),
        tenant_id: @tenant,
        household_id: @household
      },
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

  test "owner and admin may read, update, and read/write medical" do
    for role <- [:owner, :admin],
        action <- [:list, :get, :update, :read_medical, :update_medical] do
      assert :ok = Policy.authorize(staff(role), action, player()),
             "expected #{role} to #{action}"
    end

    assert :ok = Policy.authorize(staff(:owner), :list_position_options, :position_option)
    assert :ok = Policy.authorize(staff(:admin), :manage_position_options, :position_option)
  end

  test "owner and admin may not create or archive players" do
    for role <- [:owner, :admin] do
      assert {:error, :forbidden} = Policy.authorize(staff(role), :create, :player)
      assert {:error, :forbidden} = Policy.authorize(staff(role), :archive, player())
    end
  end

  test "a coach sees a player only when CoachAccess allows it" do
    coach = staff(:coach)
    target = player(%{id: "player-1"})

    Application.put_env(:sports_coach_bookings, :coach_access, HiddenCoachAccess)
    assert {:error, :forbidden} = Policy.authorize(coach, :get, target)
    assert {:error, :forbidden} = Policy.authorize(coach, :read_medical, target)

    Application.put_env(:sports_coach_bookings, :coach_access, VisibleCoachAccess)
    assert :ok = Policy.authorize(coach, :get, target)
    assert :ok = Policy.authorize(coach, :read_medical, target)
  end

  test "a coach may not mutate players or their medical data" do
    coach = staff(:coach)

    for action <- [:create, :update, :archive, :update_medical] do
      assert {:error, :forbidden} = Policy.authorize(coach, action, player())
    end

    assert {:error, :forbidden} = Policy.authorize(coach, :create, :player)
    assert :ok = Policy.authorize(coach, :list_position_options, :position_option)
  end

  test "a household manager has full CRUD over their own household's players" do
    assert :ok = Policy.authorize(customer(), :create, :player)
    assert :ok = Policy.authorize(customer(), :list, :player)

    for action <- [:get, :update, :archive, :read_medical, :update_medical] do
      assert :ok = Policy.authorize(customer(), action, player()),
             "expected manager to #{action}"
    end

    assert :ok = Policy.authorize(customer(), :list_position_options, :position_option)

    assert {:error, :forbidden} =
             Policy.authorize(customer(), :manage_position_options, :position_option)
  end

  test "another household's manager is denied on a specific player" do
    other = customer(Ecto.UUID.generate())

    for action <- [:get, :update, :archive, :read_medical, :update_medical] do
      assert {:error, :forbidden} = Policy.authorize(other, action, player())
    end
  end

  test "anonymous callers are denied everything" do
    for action <- [:list, :create, :get, :update, :archive, :read_medical, :update_medical],
        resource <- [:player, player(), :position_option] do
      assert {:error, :forbidden} = Policy.authorize(nil, action, resource)
    end
  end

  test "staff from another tenant cannot read a player" do
    foreign =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        role: :admin
      )

    assert {:error, :forbidden} = Policy.authorize(foreign, :get, player())
  end
end
