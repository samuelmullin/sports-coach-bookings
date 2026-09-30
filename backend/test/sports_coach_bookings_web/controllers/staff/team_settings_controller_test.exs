defmodule SportsCoachBookingsWeb.Staff.TeamSettingsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp patch_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> patch(path, Jason.encode!(body))
  end

  defp host(conn, slug), do: %{conn | host: "#{slug}.localhost"}

  defp signup(conn, slug) do
    resp =
      post_json(conn, ~p"/api/platform/signup", %{
        name: "Tenant #{slug}",
        slug: slug,
        email: "owner-#{slug}@test",
        password: "a very long password"
      })

    {recycle(resp), json_response(resp, 201)}
  end

  test "owner uploads a logo, changes colors, and public branding reflects it", %{conn: conn} do
    {owner, _body} = signup(conn, "brand-co")
    owner = host(owner, "brand-co")

    upload =
      post_json(owner, ~p"/api/staff/branding/uploads", %{
        filename: "logo.png",
        content_type: "image/png",
        byte_size: 1_234
      })

    assert %{"key" => key, "upload_url" => url, "method" => "PUT"} = json_response(upload, 201)
    assert url =~ key

    branded =
      patch_json(owner, ~p"/api/staff/branding", %{
        logo_key: key,
        primary_color: "#000000",
        secondary_color: "#9333ea",
        accent_color: "#f59e0b",
        background_color: "#ffffff",
        text_color: "#eeeeee",
        font_family: "inter"
      })

    assert %{"logo_key" => ^key, "warnings" => warnings} = json_response(branded, 200)
    assert is_list(warnings) and warnings != []

    public = get(host(build_conn(), "brand-co"), ~p"/api/portal/branding")

    assert %{
             "tenant" => %{"name" => "Tenant brand-co", "slug" => "brand-co"},
             "theme" => %{"primary_color" => "#000000"},
             "assets" => %{"logo_url" => logo_url}
           } = json_response(public, 200)

    assert logo_url =~ key

    etag = public |> get_resp_header("etag") |> List.first()
    assert is_binary(etag)

    cached =
      host(build_conn(), "brand-co")
      |> put_req_header("if-none-match", etag)
      |> get(~p"/api/portal/branding")

    assert response(cached, 304)
  end

  test "rejects an oversized branding upload", %{conn: conn} do
    {owner, _} = signup(conn, "upload-co")
    owner = host(owner, "upload-co")

    resp =
      post_json(owner, ~p"/api/staff/branding/uploads", %{
        filename: "huge.png",
        content_type: "image/png",
        byte_size: 3_000_000
      })

    assert json_response(resp, 422)["error"]["code"] == "file_too_large"
  end

  test "owner can invite an admin and a coach; the admin can manage but not invite owners", %{
    conn: conn
  } do
    {owner, _} = signup(conn, "team-co")
    owner = host(owner, "team-co")

    admin_invite =
      owner
      |> post_json(~p"/api/staff/team/invites", %{email: "admin@team.test", role: "admin"})

    assert %{"token" => admin_token} = json_response(admin_invite, 201)

    accepted_admin =
      build_conn()
      |> host("team-co")
      |> post_json(~p"/api/invites/#{admin_token}/accept", %{password: "a very long password"})

    assert json_response(accepted_admin, 201)["membership"]["role"] == "admin"
    admin_conn = recycle(accepted_admin) |> host("team-co")

    assert json_response(get(admin_conn, ~p"/api/staff/team"), 200)["data"] |> is_list()

    forbidden =
      post_json(admin_conn, ~p"/api/staff/team/invites", %{email: "boss@team.test", role: "owner"})

    assert json_response(forbidden, 403)["error"]["code"] == "forbidden"
  end

  test "the last owner cannot remove themselves", %{conn: conn} do
    {owner, body} = signup(conn, "last-owner-co")
    owner = host(owner, "last-owner-co")
    membership_id = body["membership"]["id"]

    resp = delete(owner, ~p"/api/staff/team/members/#{membership_id}")
    assert json_response(resp, 409)["error"]["code"] == "last_owner"
  end

  test "only the owner can transfer ownership and delete the tenant", %{conn: conn} do
    {owner, body} = signup(conn, "owner-only-co")
    owner = host(owner, "owner-only-co")

    # Invite and accept an admin.
    invite =
      post_json(owner, ~p"/api/staff/team/invites", %{email: "a2@owner-only.test", role: "admin"})

    %{"token" => token} = json_response(invite, 201)

    accepted =
      build_conn()
      |> host("owner-only-co")
      |> post_json(~p"/api/invites/#{token}/accept", %{password: "a very long password"})

    admin_membership_id = json_response(accepted, 201)["membership"]["id"]
    admin_conn = recycle(accepted) |> host("owner-only-co")

    # Owner transfers ownership.
    transfer =
      post_json(owner, ~p"/api/staff/settings/transfer_ownership", %{
        membership_id: admin_membership_id
      })

    assert json_response(transfer, 200)["role"] == "owner"

    # The new owner can delete the tenant.
    assert json_response(delete(admin_conn, ~p"/api/staff/settings"), 200)["status"] == "deleted"

    _ = body
  end

  test "settings require owner or admin", %{conn: conn} do
    {owner, _} = signup(conn, "settings-co")
    owner = host(owner, "settings-co")

    assert json_response(get(owner, ~p"/api/staff/settings"), 200)["currency_locked"] == false

    assert json_response(patch_json(owner, ~p"/api/staff/settings", %{name: "Renamed Co"}), 200)[
             "tenant"
           ]["name"] == "Renamed Co"
  end
end
