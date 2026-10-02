defmodule SportsCoachBookings.CatalogTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Catalog.DiscountTarget
  alias SportsCoachBookings.Core.Audit.Event, as: AuditEvent
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)

    actor =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: tenant.id,
        role: :owner
      )

    %{tenant: tenant, actor: actor}
  end

  describe "venues" do
    test "create, list, update, and archive", %{actor: actor} do
      assert {:ok, venue} = Catalog.create_venue(actor, %{name: "Main Field", city: "Halifax"})
      assert venue.timezone == "America/Toronto"

      assert [listed] = Catalog.list_venues(%{active: true})
      assert listed.id == venue.id

      assert {:ok, updated} = Catalog.update_venue(actor, venue.id, %{city: "Dartmouth"})
      assert updated.city == "Dartmouth"

      assert {:ok, archived} = Catalog.archive_venue(actor, venue.id)
      refute archived.active
      assert Catalog.list_venues(%{active: true}) == []
    end

    test "records an audit event", %{actor: actor} do
      assert {:ok, venue} = Catalog.create_venue(actor, %{name: "Audited Field"})

      event = Repo.one(from e in AuditEvent, where: e.action == "catalog.venue.created")
      assert event.resource_id == venue.id
      assert event.actor_type == "StaffActor"
    end

    test "fetch returns not_found for a missing venue" do
      assert {:error, :not_found} = Catalog.fetch_venue(Ecto.UUID.generate())
    end
  end

  describe "offerings" do
    test "generates a slug and filters by format and age", %{actor: actor} do
      assert {:ok, offering} =
               Catalog.create_offering(actor, %{
                 name: "Mini Kickers",
                 format: :group,
                 duration_minutes: 45,
                 min_age: 4,
                 max_age: 6
               })

      assert offering.slug == "mini-kickers"
      assert [^offering] = Catalog.list_offerings(%{age: 5})
      assert Catalog.list_offerings(%{age: 9}) == []
      assert [^offering] = Catalog.list_offerings(%{format: :group})
      assert Catalog.list_offerings(%{format: :private}) == []
    end

    test "reorders offerings", %{actor: actor} do
      a = insert(:offering, tenant_id: tenant_id())
      b = insert(:offering, tenant_id: tenant_id())

      assert {:ok, [first, second]} = Catalog.reorder_offerings(actor, [b.id, a.id])
      assert first.id == b.id
      assert second.id == a.id
    end
  end

  describe "packages" do
    test "restricts eligible offerings and defaults to all when empty", %{actor: actor} do
      offering = insert(:offering, tenant_id: tenant_id())

      assert {:ok, restricted} =
               Catalog.create_package(actor, %{
                 name: "Restricted",
                 credit_quantity: 5,
                 price: 5_000,
                 offering_ids: [offering.id]
               })

      assert Catalog.package_eligible_offering_ids(restricted.id) == [offering.id]

      assert {:ok, open} =
               Catalog.create_package(actor, %{name: "All", credit_quantity: 3, price: 3_000})

      assert Catalog.package_eligible_offering_ids(open.id) == :all
    end

    test "archiving a referenced offering keeps the package valid but hides the offering",
         %{actor: actor} do
      offering = insert(:offering, tenant_id: tenant_id())

      {:ok, package} =
        Catalog.create_package(actor, %{
          name: "Referenced",
          credit_quantity: 4,
          price: 4_000,
          offering_ids: [offering.id]
        })

      assert {:ok, _} = Catalog.archive_offering(actor, offering.id)

      assert {:ok, fetched} = Catalog.fetch_package(package.id)
      assert fetched.active
      assert Catalog.list_offerings(%{active: true}) == []
      assert Catalog.package_eligible_offering_ids(package.id) == [offering.id]
    end

    test "lists buyable packages for an offering (global + scoped, active and visible)",
         %{actor: actor} do
      a = insert(:offering, tenant_id: tenant_id())
      b = insert(:offering, tenant_id: tenant_id())

      {:ok, _global} =
        Catalog.create_package(actor, %{name: "Global 4", credit_quantity: 4, price: 4_000})

      {:ok, _scoped_a} =
        Catalog.create_package(actor, %{
          name: "A 2",
          credit_quantity: 2,
          price: 2_000,
          offering_ids: [a.id]
        })

      {:ok, _scoped_b} =
        Catalog.create_package(actor, %{
          name: "B 8",
          credit_quantity: 8,
          price: 8_000,
          offering_ids: [b.id]
        })

      {:ok, _hidden} =
        Catalog.create_package(actor, %{
          name: "Hidden",
          credit_quantity: 1,
          price: 1_000,
          visible_in_portal: false,
          offering_ids: [a.id]
        })

      {:ok, _archived} =
        Catalog.create_package(actor, %{
          name: "Archived",
          credit_quantity: 1,
          price: 1_000,
          active: false,
          offering_ids: [a.id]
        })

      assert Catalog.list_packages_for_offering(a.id) |> Enum.map(& &1.name) ==
               ["A 2", "Global 4"]

      assert Catalog.list_packages_for_offering(b.id) |> Enum.map(& &1.name) ==
               ["Global 4", "B 8"]
    end

    test "package_offering_ids returns a batched scope map", %{actor: actor} do
      offering = insert(:offering, tenant_id: tenant_id())

      {:ok, scoped} =
        Catalog.create_package(actor, %{
          name: "Scoped",
          credit_quantity: 2,
          price: 2_000,
          offering_ids: [offering.id]
        })

      {:ok, open} =
        Catalog.create_package(actor, %{name: "Open", credit_quantity: 2, price: 2_000})

      map = Catalog.package_offering_ids([scoped.id, open.id])
      assert map[scoped.id] == [offering.id]
      refute Map.has_key?(map, open.id)
    end
  end

  describe "discounts" do
    test "applies when the line matches a target", %{actor: actor} do
      offering = insert(:offering, tenant_id: tenant_id())

      {:ok, discount} =
        Catalog.create_discount(actor, %{
          code: "OFFER",
          kind: :percent,
          value: 1000,
          applies_to: :drop_ins,
          targets: [%{target_type: :offering, target_id: offering.id}]
        })

      assert %DiscountTarget{} =
               Repo.one(from t in DiscountTarget, where: t.discount_id == ^discount.id)

      assert {:ok, result} =
               Catalog.Pricing.price_lines(
                 [%{type: :drop_in, ref_id: offering.id, unit_price: 1_000, quantity: 1}],
                 "OFFER",
                 nil
               )

      assert result.discount_total == 100

      assert {:error, :not_applicable} =
               Catalog.Pricing.price_lines(
                 [%{type: :drop_in, ref_id: Ecto.UUID.generate(), unit_price: 1_000}],
                 "OFFER",
                 nil
               )
    end
  end

  describe "tax rates" do
    test "activating a rate deactivates the previous one", %{actor: actor} do
      {:ok, _first} = Catalog.create_tax_rate(actor, %{name: "HST", rate_bps: 1300})
      {:ok, second} = Catalog.create_tax_rate(actor, %{name: "GST", rate_bps: 500})

      assert [active] = Catalog.list_tax_rates(%{active: true})
      assert active.id == second.id
    end
  end

  describe "redemptions" do
    test "record_redemption is idempotent" do
      discount = insert(:discount, tenant_id: tenant_id())
      order = Ecto.UUID.generate()
      household = insert(:household).id

      Repo.with_tenant_tx(fn ->
        Catalog.Pricing.record_redemption(discount.id, household, order)
        Catalog.Pricing.record_redemption(discount.id, household, order)
      end)

      count =
        Repo.aggregate(
          from(r in SportsCoachBookings.Catalog.DiscountRedemption, where: r.order_id == ^order),
          :count
        )

      assert count == 1
    end
  end

  defp tenant_id, do: TenantContext.get_tenant_id()
end
