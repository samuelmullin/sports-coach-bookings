defmodule SportsCoachBookings.Payments.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Payments.Policy

  @actions [:connect_status, :start_onboarding, :get, :update, :update_settings]

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

  test "the owner may perform every provider-account action" do
    for action <- @actions do
      assert :ok = Policy.authorize(staff(:owner), action, :provider_account),
             "expected owner to #{action} :provider_account"
    end
  end

  test "admin, coach, customer, and anonymous are denied every action" do
    for actor <- [staff(:admin), staff(:coach), customer(), nil],
        action <- @actions do
      assert {:error, :forbidden} =
               Policy.authorize(actor, action, :provider_account),
             "expected #{inspect(actor)} to be denied #{action}"
    end
  end

  test "unknown resources are denied" do
    assert {:error, :forbidden} = Policy.authorize(staff(:owner), :connect_status, :unknown)
    assert {:error, :forbidden} = Policy.authorize(nil, :connect_status, :unknown)
  end
end
