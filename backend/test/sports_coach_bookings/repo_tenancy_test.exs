defmodule SportsCoachBookings.RepoTenancyTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Core.{MissingTenantError, TenantContext}
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Repo

  test "RLS blocks cross-tenant reads even through raw SQL" do
    assert_tenant_isolated(Event, :audit_event)
  end

  test "prepare_query raises for a tenant-scoped schema with no tenant" do
    TenantContext.clear()

    assert_raise MissingTenantError, fn ->
      Repo.all(Event)
    end
  end

  test "skip_tenant bypasses the guard (RLS still applies)" do
    TenantContext.clear()

    assert Repo.all(Event, skip_tenant: true) == []
  end

  test "non-tenant schemas can be queried without a tenant" do
    TenantContext.clear()
    assert is_list(Repo.all(SportsCoachBookings.Core.Tenant))
  end

  test "with_tenant_tx/1 sets the tenant GUC before Multi operations run" do
    tenant = insert(:tenant)
    TenantContext.put_tenant(tenant)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:event, fn _changes ->
        Event.changeset(%Event{}, %{tenant_id: tenant.id, action: "regression.multi"})
      end)

    assert {:ok, %{event: %Event{action: "regression.multi"}}} = Repo.with_tenant_tx(multi)
  end

  test "context-only helper exposes reads that forget with_tenant_tx" do
    tenant = insert(:tenant)
    put_tenant(tenant)
    player = insert(:player, tenant_id: tenant.id)

    with_tenant_context_only(tenant, fn ->
      assert Repo.get(Player, player.id) == nil
      assert {:ok, %Player{id: id}} = Players.fetch_player(player.id)
      assert id == player.id
    end)
  end
end
