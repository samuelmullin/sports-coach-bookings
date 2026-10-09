defmodule SportsCoachBookings.Websites.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Websites.Policy

  defp staff(role),
    do:
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        role: role
      )

  defp customer,
    do:
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate()
      )

  test "owners and admins manage sites and inquiries" do
    for role <- [:owner, :admin], action <- [:get, :update, :publish, :upload] do
      assert :ok = Policy.authorize(staff(role), action, :site)
    end

    for role <- [:owner, :admin], action <- [:list, :review] do
      assert :ok = Policy.authorize(staff(role), action, :contact_submission)
    end
  end

  test "coaches, customers, and anonymous callers cannot manage websites" do
    for actor <- [staff(:coach), customer(), nil] do
      assert {:error, :forbidden} = Policy.authorize(actor, :update, :site)
      assert {:error, :forbidden} = Policy.authorize(actor, :list, :contact_submission)
    end
  end

  test "published content and contact intake are public" do
    for actor <- [staff(:owner), staff(:coach), customer(), nil] do
      assert :ok = Policy.authorize(actor, :view, :published_site)
      assert :ok = Policy.authorize(actor, :create, :contact_submission)
    end
  end
end
