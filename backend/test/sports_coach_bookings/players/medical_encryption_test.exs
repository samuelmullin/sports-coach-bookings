defmodule SportsCoachBookings.Players.MedicalEncryptionTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.MedicalInfo
  alias SportsCoachBookings.Repo

  @allergies "Severely allergic to peanuts"
  @medications "Blue inhaler twice daily"

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp staff(tenant, role \\ :owner) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: role)
  end

  test "medical fields are stored as ciphertext in the database", %{tenant: tenant} do
    {:ok, player} =
      Players.create_player(nil, %{
        "household_id" => insert(:household).id,
        "first_name" => "Riley",
        "last_name" => "Doe",
        "date_of_birth" => ~D[2014-01-01]
      })

    {:ok, medical} =
      Players.upsert_medical_info(nil, player, %{
        "allergies" => @allergies,
        "medications" => @medications,
        "has_medical_info" => true
      })

    # Raw SQL bypasses cloak_ecto entirely and reads what is physically stored.
    %Postgrex.Result{rows: [[raw_allergies, raw_medications]]} =
      Repo.query!(
        "SELECT allergies, medications FROM medical_info WHERE id = $1",
        [Ecto.UUID.dump!(medical.id)]
      )

    assert is_binary(raw_allergies)
    assert is_binary(raw_medications)
    refute raw_allergies == @allergies
    refute raw_medications == @medications
    refute String.contains?(raw_allergies, "peanuts")
    refute String.contains?(raw_medications, "inhaler")

    # ...but the schema transparently decrypts on load.
    assert %MedicalInfo{allergies: @allergies, medications: @medications} =
             Repo.get!(MedicalInfo, medical.id)

    # And the staff read goes through `read_medical_info/2`.
    assert {:ok, loaded} = Players.read_medical_info(staff(tenant), player)
    assert loaded.allergies == @allergies
  end

  test "every staff medical read writes an audit event", %{tenant: tenant} do
    {:ok, player} =
      Players.create_player(nil, %{
        "household_id" => insert(:household).id,
        "first_name" => "Casey",
        "last_name" => "Doe",
        "date_of_birth" => ~D[2014-01-01]
      })

    {:ok, _} = Players.upsert_medical_info(nil, player, %{"conditions" => "Asthma"})

    auditor = staff(tenant, :admin)
    assert {:ok, _} = Players.read_medical_info(auditor, player)
    assert {:ok, _} = Players.read_medical_info(auditor, player)

    events =
      Repo.all(
        from e in Event,
          where: e.action == "player.medical.read" and e.resource_id == ^player.id
      )

    assert length(events) == 2
    assert Enum.all?(events, &(&1.actor_type == "StaffActor"))
    assert Enum.all?(events, &(&1.actor_id == auditor.staff_user_id))
    assert Enum.all?(events, &(&1.metadata == %{}))
  end
end
