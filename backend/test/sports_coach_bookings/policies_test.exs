defmodule SportsCoachBookings.PoliciesTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Policies
  alias SportsCoachBookings.Policies.CancellationPolicy
  alias SportsCoachBookings.Policies.Rules
  alias SportsCoachBookings.Policies.TenantCreatedSubscriber

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp default_rules, do: Rules.default_map()

  defp rules_with(pct) do
    Rules.default_map()
    |> Map.put("cancellation_tiers", [
      %{"min_hours_before" => 24, "credit_outcome" => "return", "money_refund_pct" => pct},
      %{"min_hours_before" => 0, "credit_outcome" => "forfeit", "money_refund_pct" => 0}
    ])
  end

  describe "create_policy/2" do
    test "the first policy becomes the default with version 1 and is audited" do
      assert {:ok, %CancellationPolicy{} = policy} =
               Policies.create_policy(nil, %{
                 "name" => "First",
                 "rules" => default_rules(),
                 "customer_facing_summary" => "Cancel early."
               })

      assert policy.is_default
      assert policy.version == 1
      assert policy.active

      assert Repo.exists?(
               from(e in Audit.Event,
                 where: e.action == "policies.policy.created" and e.resource_id == ^policy.id
               )
             )
    end

    test "rejects invalid rules" do
      assert {:error, %Ecto.Changeset{}} =
               Policies.create_policy(nil, %{
                 "name" => "Bad",
                 "rules" => Map.put(default_rules(), "cancellation_tiers", [])
               })
    end
  end

  describe "update_policy/3" do
    test "bumps the version and leaves existing snapshots unchanged" do
      {:ok, policy} = Policies.create_policy(nil, %{"name" => "A", "rules" => rules_with(100)})

      offering_id = Ecto.UUID.generate()
      before = Policies.snapshot_for(offering_id)
      assert before["policy_version"] == 1

      assert {:ok, updated} =
               Policies.update_policy(nil, policy.id, %{
                 "name" => "A",
                 "rules" => rules_with(50),
                 "customer_facing_summary" => "Changed."
               })

      assert updated.version == 2

      # The snapshot taken before the edit is unchanged...
      assert before["rules"]["cancellation_tiers"] |> Enum.at(0) |> Map.get("money_refund_pct") ==
               100

      # ...and new snapshots use the new version.
      after_snapshot = Policies.snapshot_for(offering_id)
      assert after_snapshot["policy_version"] == 2

      assert after_snapshot["rules"]["cancellation_tiers"]
             |> Enum.at(0)
             |> Map.get("money_refund_pct") == 50
    end
  end

  describe "set_default/2 and archive_policy/2" do
    test "switches the tenant default" do
      {:ok, first} = Policies.create_policy(nil, %{"name" => "A", "rules" => default_rules()})
      {:ok, second} = Policies.create_policy(nil, %{"name" => "B", "rules" => default_rules()})

      refute second.is_default
      assert Policies.get_default_policy().id == first.id

      assert {:ok, promoted} = Policies.set_default(nil, second.id)
      assert promoted.is_default
      refute Repo.get!(CancellationPolicy, first.id).is_default
      assert Policies.get_default_policy().id == second.id
    end

    test "archiving clears the default flag" do
      {:ok, policy} = Policies.create_policy(nil, %{"name" => "A", "rules" => default_rules()})
      assert {:ok, archived} = Policies.archive_policy(nil, policy.id)
      refute archived.active
      refute archived.is_default
      assert Policies.get_default_policy() == nil
    end
  end

  describe "assignments" do
    test "assigning an offering overrides the default and can be removed" do
      {:ok, default} =
        Policies.create_policy(nil, %{"name" => "Default", "rules" => rules_with(100)})

      {:ok, special} =
        Policies.create_policy(nil, %{"name" => "Special", "rules" => rules_with(25)})

      offering = insert(:offering, tenant_id: TenantContext.get_tenant_id())

      assert {:ok, assignment} = Policies.assign_offering(nil, special.id, offering.id)
      assert assignment.offering_id == offering.id
      assert Policies.assigned_offering_ids(special.id) == [offering.id]
      assert Policies.policy_for_offering(offering.id).id == special.id
      assert Policies.snapshot_for(offering.id)["policy_id"] == special.id

      assert {:ok, 1} = Policies.unassign_offering(nil, offering.id)
      assert Policies.policy_for_offering(offering.id).id == default.id
    end

    test "assigning an unknown offering is not found" do
      {:ok, policy} = Policies.create_policy(nil, %{"name" => "A", "rules" => default_rules()})
      assert {:error, :not_found} = Policies.assign_offering(nil, policy.id, Ecto.UUID.generate())
    end
  end

  describe "snapshot_for/1" do
    test "falls back to the built-in default when the tenant has no policy" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      snapshot = Policies.snapshot_for(Ecto.UUID.generate())
      assert snapshot["policy_id"] == nil
      assert snapshot["policy_version"] == 0
      assert [%{"min_hours_before" => 24} | _] = snapshot["rules"]["cancellation_tiers"]
    end

    test "summary_for_offering/1 returns the customer summary" do
      {:ok, policy} =
        Policies.create_policy(nil, %{
          "name" => "A",
          "rules" => default_rules(),
          "customer_facing_summary" => "Cancel 24h ahead."
        })

      offering = insert(:offering, tenant_id: TenantContext.get_tenant_id())
      summary = Policies.summary_for_offering(offering.id)

      assert summary.policy_id == policy.id
      assert summary.policy_name == "A"
      assert summary.summary == "Cancel 24h ahead."
    end
  end

  describe "simulate/2" do
    test "computes outcomes from hours-before" do
      {:ok, _policy} = Policies.create_policy(nil, %{"name" => "A", "rules" => default_rules()})

      assert %{outcome: early} =
               Policies.simulate(nil, %{"action" => "cancel", "hours_before" => 30})

      assert early.credit_outcome == :return

      assert %{outcome: late} =
               Policies.simulate(nil, %{"action" => "cancel", "hours_before" => 2})

      assert late.credit_outcome == :forfeit
    end

    test "computes a paid refund" do
      {:ok, _policy} = Policies.create_policy(nil, %{"name" => "A", "rules" => default_rules()})

      assert %{outcome: outcome} =
               Policies.simulate(nil, %{
                 "action" => "cancel",
                 "hours_before" => 30,
                 "payment_method" => "paid",
                 "amount_paid" => 4_000,
                 "currency" => "CAD"
               })

      assert outcome.refund_amount.amount == 4_000
      assert outcome.refund_amount.currency == "CAD"
    end
  end

  describe "tenant.created seeding" do
    test "seeds a default policy idempotently" do
      tenant = insert(:tenant)

      assert {:ok, :seeded} = Policies.seed_default_policy(tenant.id)
      assert {:ok, :already_seeded} = Policies.seed_default_policy(tenant.id)

      put_tenant(tenant)
      assert [policy] = Policies.list_policies()
      assert policy.is_default
      assert length(policy.rules.cancellation_tiers) == 2
      assert policy.rules.rebook.min_hours_before == 12
      assert policy.rules.rebook.max_rebooks_per_booking == 2
    end

    test "the subscriber handles tenant.created and is registered in config" do
      tenant = insert(:tenant)

      assert :ok =
               TenantCreatedSubscriber.handle_event("tenant.created", %{"tenant_id" => tenant.id})

      assert :ok =
               TenantCreatedSubscriber.handle_event("tenant.created", %{"tenant_id" => tenant.id})

      put_tenant(tenant)
      assert [%{is_default: true}] = Policies.list_policies()

      assert TenantCreatedSubscriber in SportsCoachBookings.Events.subscribers("tenant.created")
    end
  end
end
