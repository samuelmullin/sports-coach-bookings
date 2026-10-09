defmodule SportsCoachBookings.PlayersTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.MedicalInfo
  alias SportsCoachBookings.Players.Player

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp player_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "household_id" => insert(:household).id,
        "first_name" => "Alex",
        "last_name" => "Morgan",
        "date_of_birth" => ~D[2015-05-01]
      },
      overrides
    )
  end

  describe "create_player/2" do
    test "inserts a player and publishes player.created" do
      assert {:ok, %Player{} = player} = Players.create_player(nil, player_attrs())
      assert player.first_name == "Alex"
      assert player.active

      assert [job] = Repo.all(Oban.Job)
      assert job.args["name"] == "player.created"
      assert job.args["payload"]["player_id"] == player.id
    end

    test "rejects a household that does not exist" do
      assert {:error, changeset} =
               Players.create_player(nil, player_attrs(%{"household_id" => Ecto.UUID.generate()}))

      assert %{household_id: ["does not exist"]} = errors_on(changeset)
    end

    test "stores the household id" do
      household_id = insert(:household).id

      assert {:ok, player} =
               Players.create_player(nil, player_attrs(%{"household_id" => household_id}))

      assert player.household_id == household_id
    end
  end

  describe "update_player/3" do
    test "updates and publishes player.updated" do
      {:ok, player} = Players.create_player(nil, player_attrs())

      assert {:ok, updated} = Players.update_player(nil, player.id, %{"preferred_name" => "Lex"})
      assert updated.preferred_name == "Lex"

      names = Repo.all(from j in Oban.Job, select: j.args["name"])
      assert "player.updated" in names
    end

    test "returns not_found for a missing player" do
      assert {:error, :not_found} = Players.update_player(nil, Ecto.UUID.generate(), %{})
    end
  end

  describe "age_on/2" do
    test "computes whole years" do
      player = %Player{date_of_birth: ~D[2015-05-01]}
      assert Players.age_on(player, ~D[2026-04-30]) == 10
      assert Players.age_on(player, ~D[2026-05-01]) == 11
      assert Players.age_on(player, ~D[2026-05-02]) == 11
    end

    test "handles leap-day birthdays" do
      player = %Player{date_of_birth: ~D[2000-02-29]}
      assert Players.age_on(player, ~D[2024-02-28]) == 23
      assert Players.age_on(player, ~D[2024-02-29]) == 24
      assert Players.age_on(player, ~D[2024-03-01]) == 24
      assert Players.age_on(player, ~D[2023-02-28]) == 22
      assert Players.age_on(player, ~D[2023-03-01]) == 23
    end
  end

  describe "bookable?/1" do
    test "requires an emergency contact" do
      {:ok, player} = Players.create_player(nil, player_attrs())
      assert {:error, [:emergency_contact_required]} = Players.bookable?(player)

      {:ok, _} =
        Players.create_emergency_contact(player, %{
          "name" => "Pat",
          "phone" => "555",
          "priority" => 1
        })

      assert :ok = Players.bookable?(player)
    end

    test "reports an inactive player too" do
      {:ok, player} = Players.create_player(nil, player_attrs(%{"active" => false}))

      assert {:error, reasons} = Players.bookable?(player)
      assert :inactive_player in reasons
      assert :emergency_contact_required in reasons
    end
  end

  describe "summary_for_roster/1" do
    test "includes name, age, positions, medical flag and primary contact" do
      {:ok, player} = Players.create_player(nil, player_attrs())

      {:ok, _profile} =
        Players.upsert_profile(nil, player, %{
          "preferred_positions" => ["GK"],
          "goals" => "Have fun"
        })

      {:ok, _medical} =
        Players.upsert_medical_info(nil, player, %{"allergies" => "Peanuts"})

      {:ok, _second} =
        Players.create_emergency_contact(player, %{
          "name" => "Second",
          "phone" => "555-2",
          "priority" => 2
        })

      {:ok, _primary} =
        Players.create_emergency_contact(player, %{
          "name" => "Primary",
          "relationship" => "Parent",
          "phone" => "555-1",
          "priority" => 1
        })

      assert [summary] = Players.summary_for_roster([player.id])
      assert summary.id == player.id
      assert summary.name == "Alex"
      assert summary.preferred_positions == ["GK"]
      assert summary.has_medical_info

      assert summary.emergency_contact == %{
               name: "Primary",
               relationship: "Parent",
               phone: "555-1"
             }
    end

    test "returns an empty list for no ids" do
      assert Players.summary_for_roster([]) == []
    end
  end

  describe "search/1" do
    test "matches by name and includes inactive on request" do
      {:ok, active} = Players.create_player(nil, player_attrs(%{"first_name" => "Taylor"}))

      {:ok, _archived} =
        Players.create_player(nil, player_attrs(%{"first_name" => "Taylor", "active" => false}))

      {:ok, _other} = Players.create_player(nil, player_attrs(%{"first_name" => "Jordan"}))

      assert [found] = Players.search("taylor")
      assert found.id == active.id

      assert length(Players.search(nil)) == 2

      assert %{data: data} = Players.page_search("taylor", %{"include_inactive" => "true"})
      assert length(data) == 2
    end
  end

  describe "list_for_household/1" do
    test "returns only that household's players" do
      household = insert(:household).id
      {:ok, _a} = Players.create_player(nil, player_attrs(%{"household_id" => household}))
      {:ok, _b} = Players.create_player(nil, player_attrs())

      assert length(Players.list_for_household(household)) == 1
    end
  end

  describe "player profiles" do
    test "seeds default positions and validates against them" do
      {:ok, player} = Players.create_player(nil, player_attrs())

      assert {:ok, profile} =
               Players.upsert_profile(nil, player, %{"preferred_positions" => ["GK", "ST"]})

      assert profile.preferred_positions == ["GK", "ST"]

      assert length(Players.list_position_options()) == 8

      assert {:error, changeset} =
               Players.upsert_profile(nil, player, %{"preferred_positions" => ["QB"]})

      assert %{preferred_positions: [_]} = errors_on(changeset)
    end
  end

  describe "medical info" do
    test "upsert sets has_medical_info and read returns plaintext" do
      {:ok, player} = Players.create_player(nil, player_attrs())

      assert {:ok, %MedicalInfo{has_medical_info: true}} =
               Players.upsert_medical_info(nil, player, %{
                 "allergies" => "Peanuts",
                 "medications" => "Inhaler"
               })

      assert {:ok, medical} = Players.read_medical_info(nil, player)
      assert medical.allergies == "Peanuts"
      assert medical.medications == "Inhaler"
    end

    test "reading the audit trail records a medical read" do
      {:ok, player} = Players.create_player(nil, player_attrs())
      {:ok, _} = Players.upsert_medical_info(nil, player, %{"notes" => "Needs glasses"})

      {:ok, _} = Players.read_medical_info(nil, player)

      assert Repo.exists?(
               from e in SportsCoachBookings.Core.Audit.Event,
                 where: e.action == "player.medical.read" and e.resource_id == ^player.id
             )
    end
  end

  describe "pickups and flag" do
    test "manages authorized pickups and the no-restrictions flag" do
      {:ok, player} = Players.create_player(nil, player_attrs())

      assert {:ok, pickup} =
               Players.create_authorized_pickup(player, %{"name" => "Grandma", "phone" => "555"})

      assert [^pickup] = Players.list_authorized_pickups(player.id)

      assert {:ok, updated} =
               Players.update_authorized_pickup(player, pickup.id, %{
                 "relationship" => "Grandparent"
               })

      assert updated.relationship == "Grandparent"
      assert {:ok, _} = Players.delete_authorized_pickup(player, pickup.id)
      assert Players.list_authorized_pickups(player.id) == []

      {:ok, flagged} = Players.update_player(nil, player.id, %{"no_pickup_restrictions" => true})
      assert flagged.no_pickup_restrictions
    end
  end
end
