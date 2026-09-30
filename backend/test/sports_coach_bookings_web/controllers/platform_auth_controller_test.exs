defmodule SportsCoachBookingsWeb.PlatformAuthControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias Phoenix.ConnTest

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp host(conn, slug), do: %{conn | host: "#{slug}.localhost"}

  test "signup creates a tenant, logs in, and /me lists the membership", %{conn: conn} do
    resp =
      post_json(conn, ~p"/api/platform/signup", %{
        name: "Acme Coaching",
        slug: "acme",
        email: "owner@acme.test",
        password: "a very long password"
      })

    assert %{
             "tenant" => %{"slug" => "acme", "currency" => "CAD"},
             "staff_user" => %{"email" => "owner@acme.test"},
             "membership" => %{"role" => "owner", "status" => "active"}
           } = json_response(resp, 201)

    me = ConnTest.recycle(resp) |> get(~p"/api/platform/me")

    assert %{"staff_user" => %{"email" => "owner@acme.test"}, "memberships" => [membership]} =
             json_response(me, 200)

    assert %{"role" => "owner", "tenant" => %{"slug" => "acme"}} = membership
  end

  test "signup rejects reserved and taken slugs", %{conn: conn} do
    assert %{"error" => %{"code" => "reserved_slug"}} =
             conn
             |> post_json(~p"/api/platform/signup", %{
               name: "Admin Co",
               slug: "admin",
               email: "a@b.test",
               password: "a very long password"
             })
             |> json_response(422)
  end

  test "slug availability endpoint reports reasons" do
    insert(:tenant, slug: "taken-co")

    conn = get(build_conn(), ~p"/api/platform/slug_available?slug=fresh")
    assert %{"available" => true} = json_response(conn, 200)

    resp = get(build_conn(), ~p"/api/platform/slug_available?slug=taken-co")
    assert %{"available" => false, "reason" => "slug_taken"} = json_response(resp, 200)
  end

  test "login and logout with a session cookie", %{conn: conn} do
    signup =
      post_json(conn, ~p"/api/platform/signup", %{
        name: "Session Co",
        slug: "session-co",
        email: "owner@session.test",
        password: "a very long password"
      })

    logged_out = ConnTest.recycle(signup) |> delete(~p"/api/platform/session")
    assert response(logged_out, 204)

    bad_login =
      post_json(build_conn(), ~p"/api/platform/session", %{
        email: "owner@session.test",
        password: "wrong"
      })

    assert json_response(bad_login, 401)["error"]["code"] == "invalid_credentials"

    good_login =
      post_json(build_conn(), ~p"/api/platform/session", %{
        email: "owner@session.test",
        password: "a very long password"
      })

    assert %{"staff_user" => %{"email" => "owner@session.test"}} = json_response(good_login, 201)
  end

  test "a staff user with two memberships can use both tenants without re-login", %{conn: conn} do
    first =
      post_json(conn, ~p"/api/platform/signup", %{
        name: "First Co",
        slug: "first-co",
        email: "multi@two.test",
        password: "a very long password"
      })

    assert json_response(first, 201)

    # Same session creates a second tenant.
    second =
      ConnTest.recycle(first)
      |> post_json(~p"/api/platform/signup", %{name: "Second Co", slug: "second-co"})

    assert %{"tenant" => %{"slug" => "second-co"}} = json_response(second, 201)

    # No re-login: the same cookie accesses staff endpoints on both hosts.
    for slug <- ["first-co", "second-co"] do
      resp =
        ConnTest.recycle(second)
        |> host(slug)
        |> get(~p"/api/staff/settings")

      assert json_response(resp, 200)["tenant"]["slug"] == slug
    end
  end

  test "invite acceptance for a new user", %{conn: conn} do
    owner =
      post_json(conn, ~p"/api/platform/signup", %{
        name: "Invite Co",
        slug: "invite-co",
        email: "owner@invite.test",
        password: "a very long password"
      })

    owner_conn = ConnTest.recycle(owner) |> host("invite-co")

    invite =
      owner_conn
      |> post_json(~p"/api/staff/team/invites", %{email: "coach@invite.test", role: "coach"})

    assert %{"token" => token, "invite" => %{"role" => "coach"}} = json_response(invite, 201)

    # A brand-new user accepts on the tenant host and is logged in.
    accepted =
      build_conn()
      |> host("invite-co")
      |> post_json(~p"/api/invites/#{token}/accept", %{password: "a very long password"})

    assert %{"membership" => %{"role" => "coach"}} = json_response(accepted, 201)

    # The fresh coach session is forbidden from team management and settings.
    coach_conn = ConnTest.recycle(accepted) |> host("invite-co")

    assert json_response(get(coach_conn, ~p"/api/staff/team"), 403)["error"]["code"] ==
             "forbidden"

    assert json_response(get(coach_conn, ~p"/api/staff/settings"), 403)["error"]["code"] ==
             "forbidden"
  end
end
