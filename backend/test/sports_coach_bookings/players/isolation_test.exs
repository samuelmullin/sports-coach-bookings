defmodule SportsCoachBookings.Players.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Players.PlayerPositionOption
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.TenantIsolation

  test "players are tenant-isolated" do
    assert_tenant_isolated(Player, :player)
  end

  test "player_position_options are tenant-isolated" do
    assert_tenant_isolated(PlayerPositionOption, :player_position_option)
  end

  test "player_profiles are tenant-isolated" do
    assert_child_isolated(:player_profile, fn tenant ->
      player = insert(:player, tenant_id: tenant.id)
      insert(:player_profile, tenant_id: tenant.id, player_id: player.id)
    end)
  end

  test "emergency_contacts are tenant-isolated" do
    assert_child_isolated(:emergency_contact, fn tenant ->
      player = insert(:player, tenant_id: tenant.id)
      insert(:emergency_contact, tenant_id: tenant.id, player_id: player.id)
    end)
  end

  test "authorized_pickups are tenant-isolated" do
    assert_child_isolated(:authorized_pickup, fn tenant ->
      player = insert(:player, tenant_id: tenant.id)
      insert(:authorized_pickup, tenant_id: tenant.id, player_id: player.id)
    end)
  end

  test "medical_info are tenant-isolated" do
    assert_child_isolated(:medical_info, fn tenant ->
      player = insert(:player, tenant_id: tenant.id)
      insert(:medical_info, tenant_id: tenant.id, player_id: player.id)
    end)
  end

  defp assert_child_isolated(_factory, build_fun) do
    tenant_a = insert(:tenant)
    tenant_b = insert(:tenant)

    put_tenant(tenant_a)
    record = build_fun.(tenant_a)

    put_tenant(tenant_b)

    schema = record.__struct__
    table = schema.__schema__(:source)

    assert is_nil(Repo.get(schema, record.id)), "tenant B could read tenant A's #{table}"
    assert TenantIsolation.raw_count(table, record.id) == 0, "RLS leak on #{table}"
  end
end
