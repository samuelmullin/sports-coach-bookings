defmodule SportsCoachBookingsWeb.Portal.CatalogControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  test "lists active offerings and hides archived ones", %{conn: conn, tenant: tenant} do
    insert(:offering, tenant_id: tenant.id, name: "Active Class", active: true)
    insert(:offering, tenant_id: tenant.id, name: "Hidden Class", active: false)

    body =
      conn |> with_host(tenant.slug) |> get("/api/portal/catalog/offerings") |> json_response(200)

    names = Enum.map(body["data"], & &1["name"])

    assert names == ["Active Class"]
  end

  test "lists only active venues", %{conn: conn, tenant: tenant} do
    insert(:venue, tenant_id: tenant.id, name: "Open")
    insert(:venue, tenant_id: tenant.id, name: "Closed", active: false)

    body =
      conn |> with_host(tenant.slug) |> get("/api/portal/catalog/venues") |> json_response(200)

    assert Enum.map(body["data"], & &1["name"]) == ["Open"]
  end

  test "lists only visible, active packages", %{conn: conn, tenant: tenant} do
    insert(:package, tenant_id: tenant.id, name: "Visible")
    insert(:package, tenant_id: tenant.id, name: "Secret", visible_in_portal: false)
    insert(:package, tenant_id: tenant.id, name: "Archived", active: false)

    body =
      conn |> with_host(tenant.slug) |> get("/api/portal/catalog/packages") |> json_response(200)

    assert Enum.map(body["data"], & &1["name"]) == ["Visible"]
  end

  test "serialises package offering scope (empty list means any offering)",
       %{conn: conn, tenant: tenant} do
    offering = insert(:offering, tenant_id: tenant.id)
    scoped = insert(:package, tenant_id: tenant.id, name: "Scoped")
    insert(:package, tenant_id: tenant.id, name: "Open")

    insert(:package_offering,
      tenant_id: tenant.id,
      package_id: scoped.id,
      offering_id: offering.id
    )

    body =
      conn |> with_host(tenant.slug) |> get("/api/portal/catalog/packages") |> json_response(200)

    by_name = Map.new(body["data"], &{&1["name"], &1})
    assert by_name["Scoped"]["offering_ids"] == [offering.id]
    assert by_name["Open"]["offering_ids"] == []
  end

  test "lists only the packs valid for an offering", %{conn: conn, tenant: tenant} do
    a = insert(:offering, tenant_id: tenant.id, name: "Group A")
    b = insert(:offering, tenant_id: tenant.id, name: "Group B")

    insert(:package, tenant_id: tenant.id, name: "Global", credit_quantity: 4)
    scoped_a = insert(:package, tenant_id: tenant.id, name: "A pack", credit_quantity: 2)
    scoped_b = insert(:package, tenant_id: tenant.id, name: "B pack", credit_quantity: 8)

    insert(:package_offering,
      tenant_id: tenant.id,
      package_id: scoped_a.id,
      offering_id: a.id
    )

    insert(:package_offering,
      tenant_id: tenant.id,
      package_id: scoped_b.id,
      offering_id: b.id
    )

    body =
      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/catalog/offerings/#{a.id}/packages")
      |> json_response(200)

    assert Enum.map(body["data"], & &1["name"]) == ["A pack", "Global"]
    assert Enum.map(body["data"], & &1["offering_ids"]) == [[a.id], []]
  end
end
