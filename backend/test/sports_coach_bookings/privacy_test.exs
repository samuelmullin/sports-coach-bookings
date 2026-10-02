defmodule SportsCoachBookings.PrivacyTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Privacy
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Waivers
  alias SportsCoachBookings.Waivers.PdfCleanupWorker
  alias SportsCoachBookings.Waivers.PdfStore
  alias SportsCoachBookings.Waivers.WaiverSignature

  @password "a very long password"

  setup do
    tenant = insert(:tenant, slug: "privacy-#{System.unique_integer([:positive])}")
    put_tenant(tenant)

    email = "parent#{System.unique_integer([:positive])}@example.com"

    {:ok, reg} =
      Customers.register_customer(%{
        "first_name" => "Dana",
        "last_name" => "Reyes",
        "email" => email,
        "phone" => "+19025550111",
        "password" => @password,
        "accept_terms" => true,
        "accept_privacy" => true
      })

    actor =
      CustomerActor.new(
        customer_user_id: reg.customer_user.id,
        household_id: reg.household.id,
        tenant_id: tenant.id,
        customer_user: reg.customer_user,
        household: reg.household
      )

    {:ok, player} =
      Players.create_player(nil, %{
        household_id: reg.household.id,
        first_name: "Sam",
        last_name: "Reyes",
        date_of_birth: ~D[2015-05-01]
      })

    {:ok, _} =
      Players.create_emergency_contact(player, %{
        name: "Gran",
        relationship: "Gran",
        phone: "+19025550199",
        priority: 1
      })

    {:ok, _} = Players.upsert_medical_info(actor, player, %{allergies: "peanuts"})
    {:ok, _} = Credits.grant_complimentary(nil, reg.household.id, %{amount: 3})

    signature =
      insert(:waiver_signature, player_id: player.id, customer_user_id: reg.customer_user.id)

    insert(:cart, household_id: reg.household.id)
    insert(:delivery, email: email)

    %{tenant: tenant, reg: reg, actor: actor, player: player, email: email, signature: signature}
  end

  describe "export_household/1" do
    test "bundles the household's data and audits the export and medical read", %{
      actor: actor,
      player: player
    } do
      assert {:ok, bundle} = Privacy.export_household(actor)

      assert [%{player: %Player{id: id}} = entry] = bundle.players
      assert id == player.id
      assert entry.medical_info.allergies == "peanuts"
      assert [%{name: "Gran"}] = entry.emergency_contacts
      assert [_] = entry.waiver_signatures
      assert [_] = bundle.credit_lots
      assert [_] = bundle.credit_ledger

      actions = Repo.all(from e in Event, select: e.action)
      assert "privacy.household_exported" in actions
      assert "player.medical.read" in actions
    end

    test "does not include another household's players", %{actor: actor, tenant: tenant} do
      other = insert(:household)
      insert(:player, tenant_id: tenant.id, household_id: other.id)

      assert {:ok, %{players: [_only_mine]}} = Privacy.export_household(actor)
    end
  end

  describe "erase_household/2" do
    test "deletes players and medical data, anonymizes accounts, and audits", %{
      actor: actor,
      reg: reg,
      player: player,
      email: email,
      signature: signature
    } do
      assert {:ok, summary} = Privacy.erase_household(actor, @password)
      assert summary.players == 1
      assert summary.accounts == 1

      refute Repo.get(Player, player.id)
      assert Players.list_for_household(reg.household.id) == []
      assert Repo.aggregate(from(m in SportsCoachBookings.Players.MedicalInfo), :count) == 0

      user = Repo.get!(CustomerUser, reg.customer_user.id)
      refute user.active
      assert user.email != email
      assert user.first_name == "Erased"
      assert is_nil(user.phone)
      assert {:error, :invalid_credentials} = Customers.authenticate(email, @password)
      assert Customers.household_for_user(user.id) == nil

      scrubbed = Repo.get!(WaiverSignature, signature.id)
      assert scrubbed.signer_name_typed == "[erased]"
      assert scrubbed.user_agent == "[erased]"

      assert Repo.all(from d in Delivery, where: d.email == ^email) == []
      assert Credits.list_lots(reg.household.id) != []

      assert Repo.exists?(from e in Event, where: e.action == "privacy.household_erased")
    end

    test "queues deletion of stored waiver PDFs and the worker removes them", %{
      actor: actor,
      signature: signature
    } do
      assert {:ok, _} = Waivers.pdf_binary(signature)
      key = Repo.get!(WaiverSignature, signature.id).pdf_key
      assert {:ok, _} = PdfStore.get(key)

      assert {:ok, %{waiver_pdfs: 1}} = Privacy.erase_household(actor, @password)
      assert is_nil(Repo.get!(WaiverSignature, signature.id).pdf_key)

      assert [job] = Repo.all(from j in Oban.Job, where: j.worker == ^inspect(PdfCleanupWorker))
      assert :ok = PdfCleanupWorker.perform(job)
      assert {:error, :not_found} = PdfStore.get(key)
    end

    test "rejects a wrong password and changes nothing", %{actor: actor, player: player} do
      assert {:error, :invalid_password} = Privacy.erase_household(actor, "nope nope nope")
      assert {:error, :invalid_password} = Privacy.erase_household(actor, nil)
      assert Repo.get(Player, player.id)
    end

    test "is blocked by upcoming bookings", %{actor: actor, reg: reg, player: player} do
      starts_at =
        DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.truncate(:microsecond)

      session =
        insert(:session, starts_at: starts_at, ends_at: DateTime.add(starts_at, 3600, :second))

      insert(:booking,
        household_id: reg.household.id,
        player_id: player.id,
        session_id: session.id
      )

      assert {:error, {:erasure_blocked, [:upcoming_bookings]}} =
               Privacy.erase_household(actor, @password)

      assert Repo.get(Player, player.id)
    end

    test "a cancelled upcoming booking does not block", %{actor: actor, reg: reg, player: player} do
      starts_at =
        DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.truncate(:microsecond)

      session =
        insert(:session, starts_at: starts_at, ends_at: DateTime.add(starts_at, 3600, :second))

      insert(:booking,
        household_id: reg.household.id,
        player_id: player.id,
        session_id: session.id,
        status: :cancelled
      )

      assert {:ok, _} = Privacy.erase_household(actor, @password)
    end

    test "is blocked by an unpaid order", %{actor: actor, reg: reg} do
      insert(:order, household_id: reg.household.id, status: :pending_payment)

      assert {:error, {:erasure_blocked, [:pending_orders]}} =
               Privacy.erase_household(actor, @password)
    end

    test "only the primary member may erase", %{actor: actor, reg: reg, tenant: tenant} do
      other = insert(:customer_user, tenant_id: tenant.id)

      insert(:household_member,
        household: reg.household,
        customer_user: other,
        role: :manager
      )

      other_actor = %{actor | customer_user_id: other.id, customer_user: other}

      assert {:error, :forbidden} = Privacy.erase_household(other_actor, @password)
    end
  end
end
