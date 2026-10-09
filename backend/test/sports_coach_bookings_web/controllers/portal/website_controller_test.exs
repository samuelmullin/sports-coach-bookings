defmodule SportsCoachBookingsWeb.Portal.WebsiteControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Websites

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)

    actor =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: tenant.id,
        role: :owner
      )

    %{tenant: tenant, actor: actor}
  end

  test "unpublished sites are absent and block crawlers", %{conn: conn, tenant: tenant} do
    assert conn |> with_host(tenant.slug) |> get("/api/portal/website") |> json_response(404)

    robots = conn |> recycle() |> with_host(tenant.slug) |> get("/robots.txt")
    assert response(robots, 200) =~ "Disallow: /"

    assert conn |> recycle() |> with_host(tenant.slug) |> get("/sitemap.xml") |> response(404)
  end

  test "published content, robots, and sitemap share the tenant host", %{
    conn: conn,
    tenant: tenant,
    actor: actor
  } do
    assert {:ok, _site} =
             Websites.update_draft(actor, %{
               "content" => %{"hero" => %{"title" => "Train with purpose"}}
             })

    assert {:ok, _site} = Websites.publish(actor)

    body = conn |> with_host(tenant.slug) |> get("/api/portal/website") |> json_response(200)
    assert body["content"]["hero"]["title"] == "Train with purpose"

    robots = conn |> recycle() |> with_host(tenant.slug) |> get("/robots.txt")
    assert response(robots, 200) =~ "Sitemap: http://#{tenant.slug}.localhost/sitemap.xml"

    sitemap = conn |> recycle() |> with_host(tenant.slug) |> get("/sitemap.xml")
    assert response(sitemap, 200) =~ "http://#{tenant.slug}.localhost/contact"
  end

  test "contact input rejects header line breaks", %{conn: conn, tenant: tenant} do
    response =
      conn
      |> with_host(tenant.slug)
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/portal/website/contact",
        Jason.encode!(%{
          name: "A Parent",
          email: "parent@example.test",
          subject: "Hello\r\nBcc: attacker@example.test",
          message: "I would like to ask about a training session."
        })
      )

    assert json_response(response, 422)["error"]["details"]["fields"]["subject"]
  end
end
