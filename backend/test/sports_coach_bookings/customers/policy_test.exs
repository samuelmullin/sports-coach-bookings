defmodule SportsCoachBookings.Customers.PolicyTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.Household
  alias SportsCoachBookings.Customers.HouseholdMember
  alias SportsCoachBookings.Customers.Policy

  @tenant_id "11111111-1111-7111-8111-111111111111"

  defp staff(role, tenant_id \\ @tenant_id) do
    StaffActor.new(
      staff_user_id: Ecto.UUID.generate(),
      tenant_id: tenant_id,
      role: role
    )
  end

  defp customer(tenant_id \\ @tenant_id, household_id \\ "hh-1") do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: household_id,
      tenant_id: tenant_id
    )
  end

  defp customer_user(tenant_id), do: %CustomerUser{id: Ecto.UUID.generate(), tenant_id: tenant_id}

  defp household(tenant_id), do: %Household{id: Ecto.UUID.generate(), tenant_id: tenant_id}

  defp member(tenant_id, household_id) do
    %HouseholdMember{
      id: Ecto.UUID.generate(),
      tenant_id: tenant_id,
      household_id: household_id
    }
  end

  describe "customer administration" do
    test "owners and admins may search, view, edit, reset, and deactivate" do
      for role <- [:owner, :admin],
          action <- [:list, :search, :get, :update, :reset_password, :deactivate, :reactivate] do
        assert :ok = Policy.authorize(staff(role), action, :customer)
        assert :ok = Policy.authorize(staff(role), action, customer_user(@tenant_id))
      end
    end

    test "staff of another tenant cannot touch a customer" do
      assert {:error, :forbidden} =
               Policy.authorize(staff(:admin, "other-tenant"), :get, customer_user(@tenant_id))
    end

    test "coaches, customers, and anonymous are denied customer admin" do
      actors = [staff(:coach), customer(), nil]

      for actor <- actors, action <- [:list, :get, :update, :reset_password, :deactivate] do
        assert {:error, :forbidden} = Policy.authorize(actor, action, :customer)
        assert {:error, :forbidden} = Policy.authorize(actor, action, customer_user(@tenant_id))
      end
    end
  end

  describe "households" do
    test "owners and admins may list and view households in their tenant" do
      for role <- [:owner, :admin] do
        assert :ok = Policy.authorize(staff(role), :list, :household)
        assert :ok = Policy.authorize(staff(role), :get, household(@tenant_id))
        assert :ok = Policy.authorize(staff(role), :list_members, household(@tenant_id))
      end

      assert {:error, :forbidden} =
               Policy.authorize(staff(:admin), :get, household("other-tenant"))
    end

    test "customers manage only their own household" do
      actor = customer(@tenant_id, "hh-1")

      assert :ok = Policy.authorize(actor, :get, :household)
      assert :ok = Policy.authorize(actor, :invite, :household)
      assert :ok = Policy.authorize(actor, :leave, :household)
      assert :ok = Policy.authorize(actor, :get, %Household{id: "hh-1", tenant_id: @tenant_id})
      assert :ok = Policy.authorize(actor, :remove_member, member(@tenant_id, "hh-1"))
      assert :ok = Policy.authorize(actor, :transfer_primary, member(@tenant_id, "hh-1"))

      assert {:error, :forbidden} =
               Policy.authorize(actor, :get, %Household{id: "hh-2", tenant_id: @tenant_id})

      assert {:error, :forbidden} =
               Policy.authorize(actor, :remove_member, member(@tenant_id, "hh-2"))
    end

    test "coaches and anonymous cannot manage households" do
      for actor <- [staff(:coach), nil] do
        assert {:error, :forbidden} = Policy.authorize(actor, :list, :household)
        assert {:error, :forbidden} = Policy.authorize(actor, :get, household(@tenant_id))
        assert {:error, :forbidden} = Policy.authorize(actor, :invite, :household)
      end
    end
  end

  describe "account self-service" do
    test "a customer may manage their own account" do
      actor = customer()

      for action <- [:get, :update, :update_password, :update_email, :notification_preferences] do
        assert :ok = Policy.authorize(actor, action, :account)
      end
    end

    test "staff and anonymous cannot use the customer self-service account" do
      for actor <- [staff(:owner), staff(:coach), nil],
          action <- [:get, :update, :update_password] do
        assert {:error, :forbidden} = Policy.authorize(actor, action, :account)
      end
    end
  end
end
