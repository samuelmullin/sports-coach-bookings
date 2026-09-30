defmodule SportsCoachBookings.Waivers.PolicyTest do
  use ExUnit.Case, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Waivers.Policy

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
      %Player{id: Ecto.UUID.generate(), tenant_id: @tenant, household_id: @household},
      overrides
    )
  end

  @staff_resource_actions [:list, :get, :create, :update, :archive, :publish, :preview]

  test "owner and admin may do everything on every resource" do
    resources = [:waiver_template, :waiver_version, :waiver_signature, player()]

    for role <- [:owner, :admin],
        action <- Policy.actions(),
        resource <- resources do
      assert :ok = Policy.authorize(staff(role), action, resource),
             "expected #{role} to #{action} on #{inspect(resource)}"
    end
  end

  test "a coach has read-only access to templates, versions, and signatures" do
    coach = staff(:coach)

    for resource <- [:waiver_template, :waiver_version, :waiver_signature],
        action <- [:list, :get, :preview, :list_signatures, :download_pdf] do
      assert :ok = Policy.authorize(coach, action, resource),
             "expected coach to #{action} #{inspect(resource)}"
    end

    for resource <- [:waiver_template, :waiver_version, :waiver_signature],
        action <- [:create, :update, :archive, :publish] do
      assert {:error, :forbidden} = Policy.authorize(coach, action, resource)
    end
  end

  test "a household manager can view published bodies and act for own players" do
    manager = customer()
    own = player()

    assert :ok = Policy.authorize(manager, :status, :waiver_status)
    assert :ok = Policy.authorize(manager, :view_version, :waiver_version)

    for action <- [:list_player_waivers, :sign, :download_pdf] do
      assert :ok = Policy.authorize(manager, action, own)
    end
  end

  test "a household manager cannot act for another household's player" do
    other = customer(Ecto.UUID.generate())

    for action <- [:list_player_waivers, :sign, :download_pdf] do
      assert {:error, :forbidden} = Policy.authorize(other, action, player())
    end
  end

  test "a household manager cannot manage templates" do
    manager = customer()

    for action <- @staff_resource_actions do
      assert {:error, :forbidden} = Policy.authorize(manager, action, :waiver_template)
    end
  end

  test "staff from another tenant cannot read a player" do
    foreign =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        role: :admin
      )

    assert {:error, :forbidden} = Policy.authorize(foreign, :sign, player())
  end

  test "anonymous callers are denied everything" do
    resources = [:waiver_template, :waiver_version, :waiver_signature, :waiver_status, player()]

    for action <- Policy.actions(), resource <- resources do
      assert {:error, :forbidden} = Policy.authorize(nil, action, resource)
    end
  end
end
