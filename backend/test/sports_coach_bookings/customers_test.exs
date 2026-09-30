defmodule SportsCoachBookings.CustomersTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.CustomerUserToken
  alias SportsCoachBookings.Customers.HouseholdMember

  @password "a very long password"

  defp registration_attrs(email, overrides \\ %{}) do
    Map.merge(
      %{
        "first_name" => "Dana",
        "last_name" => "Reyes",
        "email" => email,
        "phone" => "+19025550111",
        "password" => @password,
        "accept_terms" => true,
        "accept_privacy" => true
      },
      overrides
    )
  end

  defp register(tenant, email \\ nil) do
    email = email || "parent#{System.unique_integer([:positive])}@example.com"
    put_tenant(tenant)

    {:ok, result} = Customers.register_customer(registration_attrs(email))
    result
  end

  defp actor_for(tenant, result) do
    CustomerActor.new(
      customer_user_id: result.customer_user.id,
      household_id: result.household.id,
      tenant_id: tenant.id,
      customer_user: result.customer_user,
      household: result.household
    )
  end

  describe "registration" do
    test "creates the user, household, and primary membership; publishes the event" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:ok, result} =
               Customers.register_customer(registration_attrs("dana@example.com"))

      assert result.customer_user.email == "dana@example.com"
      assert result.customer_user.hashed_password =~ "pbkdf2_sha256$"
      refute Customers.require_confirmed(result.customer_user) == :ok
      assert result.customer_user.terms_version
      assert result.customer_user.terms_accepted_at
      assert result.member.role == :primary
      assert result.member.household_id == result.household.id

      assert [job] = event_jobs("customer.registered")
      assert job.args["payload"]["customer_user_id"] == result.customer_user.id
    end

    test "requires terms and privacy acceptance, and a valid phone" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:error, changeset} =
               Customers.register_customer(
                 registration_attrs("x@example.com", %{"accept_terms" => false})
               )

      assert %{accept_terms: _} = errors_on(changeset)

      assert {:error, changeset} =
               Customers.register_customer(
                 registration_attrs("x@example.com", %{"phone" => "555"})
               )

      assert "Enter a valid phone number for the selected country." in errors_on(changeset).phone
    end

    test "composes a national number with the selected country into E.164" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:ok, result} =
               Customers.register_customer(
                 registration_attrs("national@example.com", %{
                   "phone" => "9025550111",
                   "phone_country" => "CA"
                 })
               )

      assert result.customer_user.phone == "+19025550111"
    end

    test "accepts a full E.164 number and leaves the phone optional when blank" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:ok, e164} =
               Customers.register_customer(
                 registration_attrs("e164@example.com", %{"phone" => "+447911123456"})
               )

      assert e164.customer_user.phone == "+447911123456"

      assert {:ok, blank} =
               Customers.register_customer(
                 registration_attrs("blank@example.com", %{"phone" => nil})
               )

      assert blank.customer_user.phone == nil
    end

    test "records the current terms and privacy versions" do
      tenant = insert(:tenant)
      result = register(tenant)

      assert result.customer_user.terms_version == CustomerUser.terms_version()

      assert result.customer_user.privacy_version == CustomerUser.privacy_version()
    end
  end

  describe "authentication and sessions" do
    test "authenticates by email and rejects bad credentials" do
      tenant = insert(:tenant)
      result = register(tenant)

      assert {:ok, user} = Customers.authenticate(result.customer_user.email, @password)
      assert user.id == result.customer_user.id

      assert {:error, :invalid_credentials} =
               Customers.authenticate(result.customer_user.email, "nope")

      assert {:error, :invalid_credentials} = Customers.authenticate("nobody@example.com", "nope")
    end

    test "session tokens round-trip and are deleted on logout" do
      tenant = insert(:tenant)
      result = register(tenant)

      {plaintext, _} = Customers.create_session_token(result.customer_user)
      assert {:ok, %{id: id}} = Customers.get_customer_user_by_session_token(plaintext)
      assert id == result.customer_user.id

      assert :ok = Customers.delete_session_token(plaintext)
      assert :error = Customers.get_customer_user_by_session_token(plaintext)
    end
  end

  describe "confirmation and reset" do
    test "confirms the email and clears require_confirmed" do
      tenant = insert(:tenant)
      result = register(tenant)

      token = Customers.create_confirm_token(result.customer_user)
      assert {:ok, confirmed} = Customers.confirm_customer_user(token)
      assert confirmed.confirmed_at
      assert :ok = Customers.require_confirmed(confirmed)
      assert {:error, :invalid_token} = Customers.confirm_customer_user(token)
    end

    test "resets the password" do
      tenant = insert(:tenant)
      result = register(tenant)

      {plaintext, changeset} = CustomerUserToken.build(result.customer_user, "reset_password")
      {:ok, _} = Repo.insert(changeset)

      assert {:ok, _} =
               Customers.reset_password(plaintext, %{"password" => "an even longer password"})

      assert {:ok, _} =
               Customers.authenticate(result.customer_user.email, "an even longer password")

      assert {:error, :invalid_token} =
               Customers.reset_password(plaintext, %{"password" => "another long password"})
    end

    test "changing email clears confirmation and emails the new address" do
      tenant = insert(:tenant)
      result = register(tenant)

      assert {:ok, %{customer_user: user, confirmation_token: token}} =
               Customers.change_email(result.customer_user, %{"email" => "new@example.com"})

      assert user.email == "new@example.com"
      assert user.confirmed_at == nil
      assert is_binary(token)
      assert {:error, :email_unconfirmed} = Customers.require_confirmed(user)
    end
  end

  describe "deactivation" do
    test "blocks login and revokes sessions; data is retained" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      result = register(tenant)
      {plaintext, _} = Customers.create_session_token(result.customer_user)

      admin = admin_actor(tenant)
      assert {:ok, deactivated} = Customers.deactivate_customer(admin, result.customer_user.id)
      refute deactivated.active

      assert {:error, :deactivated} =
               Customers.authenticate(result.customer_user.email, @password)

      assert :error = Customers.get_customer_user_by_session_token(plaintext)
      assert Customers.get_customer_user(result.customer_user.id)
      assert Repo.get_by(Event, action: "customer.deactivated")
    end
  end

  describe "tenant isolation of identity" do
    test "the same email at two tenants is two independent accounts" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      a = register(tenant_a, "same@example.com")
      b = register(tenant_b, "same@example.com")

      refute a.customer_user.id == b.customer_user.id

      # The session minted at A cannot resolve at B.
      put_tenant(tenant_a)
      {plaintext, _} = Customers.create_session_token(a.customer_user)
      assert {:ok, _} = Customers.get_customer_user_by_session_token(plaintext)

      put_tenant(tenant_b)
      assert :error = Customers.get_customer_user_by_session_token(plaintext)
    end
  end

  describe "households and invitations" do
    test "household_for_user and list_manager_emails" do
      tenant = insert(:tenant)
      result = register(tenant)
      actor = actor_for(tenant, result)

      assert Customers.household_for_user(result.customer_user.id).id == result.household.id
      assert Customers.list_manager_emails(actor.household_id) == [result.customer_user.email]
    end

    test "invites a new adult who registers and joins; publishes both events" do
      tenant = insert(:tenant)
      result = register(tenant)
      actor = actor_for(tenant, result)

      assert {:ok, %{invite: invite, token: token}} =
               Customers.invite_member(actor, %{
                 "email" => "co@example.com",
                 "relationship" => "parent"
               })

      assert invite.relationship == "parent"
      assert [job] = event_jobs("household.member_invited")
      assert job.args["payload"]["email"] == "co@example.com"

      assert {:ok, %{customer_user: user, household: household, member: member}} =
               Customers.accept_invite(token, registration_attrs("co@example.com"))

      assert household.id == actor.household_id
      assert member.role == :manager
      assert user.confirmed_at
      assert [job] = event_jobs("household.member_joined")
      assert job.args["payload"]["customer_user_id"] == user.id
    end

    test "an existing account joining when it has no other household" do
      tenant = insert(:tenant)
      result = register(tenant)
      actor = actor_for(tenant, result)

      standalone = insert(:customer_user, tenant_id: tenant.id)

      {:ok, %{token: token}} =
        Customers.invite_member(actor, %{"email" => standalone.email, "relationship" => "aunt"})

      assert {:ok, %{customer_user: user, member: member}} =
               Customers.accept_invite(token, %{}, customer_user: standalone)

      assert user.id == standalone.id
      assert member.household_id == actor.household_id
    end

    test "an account that already has a household cannot join another" do
      tenant = insert(:tenant)
      first = register(tenant, "first@example.com")
      second = register(tenant, "second@example.com")
      actor = actor_for(tenant, first)

      {:ok, %{token: token}} =
        Customers.invite_member(actor, %{"email" => "second@example.com"})

      assert {:error, :already_has_household} =
               Customers.accept_invite(token, %{}, customer_user: second.customer_user)
    end

    test "a removed manager loses access immediately" do
      tenant = insert(:tenant)
      result = register(tenant)
      actor = actor_for(tenant, result)
      manager = insert(:customer_user, tenant_id: tenant.id)

      member = join_household(tenant, actor.household_id, manager, :manager)

      assert {:ok, _} = Customers.remove_member(actor, member.id)
      assert Customers.household_for_user(manager.id) == nil
      assert {:error, :not_found} = Customers.remove_member(actor, member.id)
    end

    test "a manager may leave but the primary must transfer first" do
      tenant = insert(:tenant)
      result = register(tenant)
      primary_actor = actor_for(tenant, result)
      manager = insert(:customer_user, tenant_id: tenant.id)

      member = join_household(tenant, primary_actor.household_id, manager, :manager)

      manager_actor =
        CustomerActor.new(
          customer_user_id: manager.id,
          household_id: member.household_id,
          tenant_id: tenant.id
        )

      assert {:ok, _} = Customers.leave_household(manager_actor)
      assert {:error, :forbidden} = Customers.leave_household(primary_actor)
    end

    test "transfer_primary promotes the target and demotes the caller (primary only)" do
      tenant = insert(:tenant)
      result = register(tenant)
      actor = actor_for(tenant, result)
      manager = insert(:customer_user, tenant_id: tenant.id)

      member = join_household(tenant, actor.household_id, manager, :manager)

      assert {:ok, promoted} = Customers.transfer_primary(actor, member.id)
      assert promoted.role == :primary
      assert Customers.get_membership_for_user(actor.customer_user_id).role == :manager
      assert Repo.get_by(Event, action: "household.primary_transferred")
    end
  end

  describe "admin search" do
    test "searches customers and households by term" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      insert(:customer_user, tenant_id: tenant.id, first_name: "Wendy", last_name: "Fernandez")
      result = register(tenant, "findme@example.com")

      assert Enum.any?(Customers.list_customers("findme"), &(&1.id == result.customer_user.id))
      assert Customers.list_customers("Wendy") != []

      households = Customers.list_households("Reyes")
      assert Enum.any?(households, &String.contains?(&1.name || "", "Reyes"))
    end

    test "admin update is audited" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      result = register(tenant)
      admin = admin_actor(tenant)

      assert {:ok, updated} =
               Customers.admin_update_customer(admin, result.customer_user.id, %{
                 "first_name" => "Renamed"
               })

      assert updated.first_name == "Renamed"
      assert Repo.get_by(Event, action: "customer.updated")
    end
  end

  defp admin_actor(tenant) do
    StaffActor.new(
      staff_user_id: Ecto.UUID.generate(),
      tenant_id: tenant.id,
      role: :admin
    )
  end

  defp join_household(tenant, household_id, customer_user, role) do
    {:ok, member} =
      %HouseholdMember{}
      |> HouseholdMember.changeset(%{
        tenant_id: tenant.id,
        household_id: household_id,
        customer_user_id: customer_user.id,
        role: role,
        relationship: "parent"
      })
      |> Repo.insert()

    member
  end

  defp event_jobs(name) do
    Repo.all(Oban.Job) |> Enum.filter(&(&1.args["name"] == name))
  end
end
