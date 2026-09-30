defmodule SportsCoachBookings.StaffTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Staff.StaffUserToken

  describe "identity" do
    test "registers and authenticates a staff user" do
      attrs = %{"email" => "Owner@Example.com", "password" => "a very long password"}

      assert {:ok, user} = Staff.register_staff_user(attrs)
      assert user.email == "Owner@Example.com"
      assert user.hashed_password =~ "pbkdf2_sha256$"

      assert {:ok, authenticated} =
               Staff.authenticate("owner@example.com", "a very long password")

      assert authenticated.id == user.id

      assert {:error, :invalid_credentials} = Staff.authenticate(user.email, "wrong password")
      assert {:error, :invalid_credentials} = Staff.authenticate("nobody@example.com", "whatever")
    end

    test "rejects short passwords and duplicate emails" do
      assert {:error, %Ecto.Changeset{}} =
               Staff.register_staff_user(%{"email" => "a@example.com", "password" => "short"})

      {:ok, _} =
        Staff.register_staff_user(%{
          "email" => "dup@example.com",
          "password" => "a very long password"
        })

      assert {:error, %Ecto.Changeset{}} =
               Staff.register_staff_user(%{
                 "email" => "dup@example.com",
                 "password" => "another long password"
               })
    end

    test "session tokens round-trip and are deleted on logout" do
      {:ok, user} =
        Staff.register_staff_user(%{
          "email" => "s@example.com",
          "password" => "a very long password"
        })

      {plaintext, _token} = Staff.create_session_token(user)

      assert {:ok, %{id: id}} = Staff.get_staff_user_by_session_token(plaintext)
      assert id == user.id

      assert :ok = Staff.delete_session_token(plaintext)
      assert :error = Staff.get_staff_user_by_session_token(plaintext)
      assert :error = Staff.get_staff_user_by_session_token("nonsense")
    end

    test "confirmation flow marks the email confirmed" do
      {:ok, user} =
        Staff.register_staff_user(%{
          "email" => "c@example.com",
          "password" => "a very long password"
        })

      refute user.confirmed_at
      token = Staff.create_confirm_token(user)

      assert {:ok, confirmed} = Staff.confirm_staff_user(token)
      assert confirmed.confirmed_at
      assert {:error, :invalid_token} = Staff.confirm_staff_user(token)
    end

    test "password reset flow changes the password" do
      {:ok, user} =
        Staff.register_staff_user(%{
          "email" => "r@example.com",
          "password" => "a very long password"
        })

      plaintext = reset_token(user)

      assert {:ok, _} =
               Staff.reset_password(plaintext, %{"password" => "an even longer password"})

      assert {:ok, _} = Staff.authenticate(user.email, "an even longer password")

      assert {:error, :invalid_token} =
               Staff.reset_password(plaintext, %{"password" => "nope nope nope"})
    end
  end

  describe "memberships" do
    test "a staff user with memberships in two tenants sees both without re-login" do
      {:ok, user} =
        Staff.register_staff_user(%{
          "email" => "multi@example.com",
          "password" => "a very long password"
        })

      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      put_tenant(tenant_a)
      insert(:membership, tenant_id: tenant_a.id, staff_user: user, role: :owner)

      put_tenant(tenant_b)
      insert(:membership, tenant_id: tenant_b.id, staff_user: user, role: :coach)

      TenantContext.clear()
      memberships = Staff.list_memberships(user)

      assert Enum.map(memberships, & &1.tenant_id) |> Enum.sort() ==
               Enum.sort([tenant_a.id, tenant_b.id])
    end

    test "list_coaches only returns active coaches" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      insert(:membership, tenant_id: tenant.id, role: :coach)
      insert(:membership, tenant_id: tenant.id, role: :coach, status: :removed)
      insert(:membership, tenant_id: tenant.id, role: :admin)

      coaches = Staff.list_coaches()
      assert length(coaches) == 1
      assert hd(coaches).role == :coach
    end
  end

  describe "invitations" do
    test "invites a new user and publishes staff.invited" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)

      assert {:ok, %{invite: invite, token: token}} =
               Staff.invite_staff(actor, %{email: "new@example.com", role: :admin})

      assert invite.role == :admin
      assert is_binary(token)
      assert [job] = event_jobs("staff.invited")
      assert job.args["payload"]["email"] == "new@example.com"
    end

    test "accepting as a new user registers, joins, and publishes staff.joined" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)

      {:ok, %{token: token}} =
        Staff.invite_staff(actor, %{email: "new@example.com", role: :coach})

      assert {:ok, %{membership: membership, staff_user: user}} =
               Staff.accept_invite(token, %{"password" => "a very long password"})

      assert membership.role == :coach
      assert membership.status == :active
      assert user.email == "new@example.com"
      assert user.confirmed_at
      assert [_] = event_jobs("staff.joined")

      assert {:error, :invalid_invite} =
               Staff.accept_invite(token, %{"password" => "another long password"})
    end

    test "accepting as an existing logged-in user joins without creating a new account" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)
      existing = insert(:staff_user)

      {:ok, %{token: token}} =
        Staff.invite_staff(actor, %{email: existing.email, role: :admin})

      assert {:ok, %{staff_user: user, membership: membership}} =
               Staff.accept_invite(token, %{}, staff_user: existing)

      assert user.id == existing.id
      assert membership.role == :admin
    end

    test "an email with an active membership cannot be invited" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)
      existing = insert(:staff_user)
      insert(:membership, tenant_id: tenant.id, staff_user: existing, role: :coach)

      assert {:error, :already_member} =
               Staff.invite_staff(actor, %{email: existing.email, role: :admin})
    end

    test "only an owner may invite an owner" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      admin_user = insert(:staff_user)

      admin_membership =
        insert(:membership, tenant_id: tenant.id, staff_user: admin_user, role: :admin)

      admin =
        StaffActor.new(
          staff_user_id: admin_user.id,
          membership: admin_membership,
          tenant_id: tenant.id,
          role: :admin
        )

      assert {:error, :forbidden} =
               Staff.invite_staff(admin, %{email: "boss@example.com", role: :owner})

      assert {:ok, _} = Staff.invite_staff(admin, %{email: "coach@example.com", role: :coach})
    end

    test "expired invites cannot be accepted" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)

      {:ok, %{token: token}} =
        Staff.invite_staff(actor, %{email: "late@example.com", role: :coach})

      past = DateTime.add(DateTime.utc_now(), -1, :day)
      Repo.update_all(SportsCoachBookings.Staff.StaffInvite, set: [expires_at: past])

      # Re-query through the context (tenant context is set).
      assert {:error, :expired_invite} =
               Staff.accept_invite(token, %{"password" => "a very long password"})
    end
  end

  describe "role changes and removal" do
    test "changes a member's role and audits it" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)
      member = insert(:membership, tenant_id: tenant.id, role: :coach)

      assert {:ok, updated} = Staff.change_role(actor, member.id, :admin)
      assert updated.role == :admin

      assert Repo.get_by(SportsCoachBookings.Core.Audit.Event, action: "staff.role_changed")
    end

    test "the last owner cannot be demoted or removed" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)
      owner_membership = actor.membership

      assert {:error, :last_owner} = Staff.change_role(actor, owner_membership.id, :admin)
      assert {:error, :last_owner} = Staff.remove_membership(actor, owner_membership.id)
    end

    test "an owner may be removed when another owner remains" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)
      second = insert(:membership, tenant_id: tenant.id, role: :owner)

      assert {:ok, removed} = Staff.remove_membership(actor, second.id)
      assert removed.status == :removed
      assert [_] = event_jobs("staff.removed")
    end

    test "transfer ownership promotes the target and demotes the previous owner" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      actor = owner_actor(tenant)
      target = insert(:membership, tenant_id: tenant.id, role: :coach)

      assert {:ok, promoted} = Staff.transfer_ownership(actor, target.id)
      assert promoted.role == :owner

      demoted = Repo.get(SportsCoachBookings.Staff.Membership, actor.membership.id)
      assert demoted.role == :admin

      assert Repo.get_by(SportsCoachBookings.Core.Audit.Event,
               action: "tenant.ownership_transferred"
             )
    end
  end

  ## Helpers

  defp owner_actor(tenant) do
    user = insert(:staff_user)
    membership = insert(:membership, tenant_id: tenant.id, staff_user: user, role: :owner)

    StaffActor.new(
      staff_user_id: user.id,
      membership: membership,
      tenant_id: tenant.id,
      role: :owner
    )
  end

  defp reset_token(user) do
    {plaintext, changeset} = StaffUserToken.build(user, "reset_password")
    {:ok, _} = Repo.insert(changeset)
    plaintext
  end

  defp event_jobs(name) do
    Repo.all(Oban.Job)
    |> Enum.filter(&(&1.args["name"] == name))
  end
end
