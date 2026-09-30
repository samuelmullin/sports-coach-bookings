defmodule SportsCoachBookingsWeb.PortalAccountControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias Phoenix.ConnTest
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.DataCase

  @password "a very long password"

  defp host(conn, slug), do: %{conn | host: "#{slug}.localhost"}

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp json_patch(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> patch(path, Jason.encode!(body))
  end

  defp json_put(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(body))
  end

  defp registration(email, overrides \\ %{}) do
    Map.merge(
      %{
        first_name: "Dana",
        last_name: "Reyes",
        email: email,
        phone: "+19025550111",
        password: @password,
        accept_terms: true,
        accept_privacy: true
      },
      overrides
    )
  end

  describe "registration and login" do
    test "registers a customer on the tenant host and logs in", %{conn: conn} do
      insert(:tenant, slug: "acme")

      resp =
        conn
        |> host("acme")
        |> json_post("/api/portal/registrations", registration("dana@example.com"))

      assert %{
               "customer_user" => %{"email" => "dana@example.com", "confirmed" => false},
               "household" => %{"id" => _}
             } = json_response(resp, 201)

      login =
        build_conn()
        |> host("acme")
        |> json_post("/api/portal/session", %{email: "dana@example.com", password: @password})

      assert %{"customer_user" => %{"email" => "dana@example.com"}} = json_response(login, 201)

      account = ConnTest.recycle(login) |> host("acme") |> get("/api/portal/account")
      assert json_response(account, 200)["customer_user"]["email"] == "dana@example.com"
    end

    test "rejects bad credentials and validates registration fields", %{conn: conn} do
      insert(:tenant, slug: "acme")

      bad =
        conn
        |> host("acme")
        |> json_post("/api/portal/session", %{email: "nobody@example.com", password: "nope"})

      assert json_response(bad, 401)["error"]["code"] == "invalid_credentials"

      invalid =
        build_conn()
        |> host("acme")
        |> json_post("/api/portal/registrations", registration("x@example.com", %{phone: "555"}))

      assert json_response(invalid, 422)["error"]["code"] == "validation_error"
    end

    test "the same email at two tenants is two independent accounts and the session is host-scoped",
         %{conn: conn} do
      insert(:tenant, slug: "alpha")
      insert(:tenant, slug: "beta")

      a =
        conn
        |> host("alpha")
        |> json_post("/api/portal/registrations", registration("same@example.com"))

      assert json_response(a, 201)

      b =
        ConnTest.recycle(a)
        |> host("beta")
        |> json_post("/api/portal/registrations", registration("same@example.com"))

      assert json_response(b, 201)

      # The alpha session is not a valid beta session.
      probe = ConnTest.recycle(a) |> host("beta") |> get("/api/portal/account")
      assert json_response(probe, 403)["error"]["code"] == "forbidden"

      # The alpha session still works on alpha.
      good = ConnTest.recycle(a) |> host("alpha") |> get("/api/portal/account")
      assert json_response(good, 200)["customer_user"]["email"] == "same@example.com"
    end
  end

  describe "email confirmation guard" do
    test "an unconfirmed customer can log in but the purchase guard returns 403 email_unconfirmed",
         %{conn: conn} do
      tenant = insert(:tenant, slug: "acme")

      signup =
        conn
        |> host("acme")
        |> json_post("/api/portal/registrations", registration("dana@example.com"))

      assert json_response(signup, 201)

      # Login is allowed even though the email is unconfirmed.
      login =
        build_conn()
        |> host("acme")
        |> json_post("/api/portal/session", %{email: "dana@example.com", password: @password})

      assert json_response(login, 201)

      guard =
        ConnTest.recycle(login) |> host("acme") |> post("/api/portal/account/purchase_guard")

      assert json_response(guard, 403)["error"]["code"] == "email_unconfirmed"

      # Confirming clears the guard.
      DataCase.put_tenant(tenant)
      user = Customers.get_customer_user_by_email("dana@example.com")
      token = Customers.create_confirm_token(user)

      confirm =
        build_conn() |> host("acme") |> json_post("/api/portal/confirmation", %{token: token})

      assert json_response(confirm, 200)["customer_user"]["confirmed"] == true

      ok = ConnTest.recycle(login) |> host("acme") |> post("/api/portal/account/purchase_guard")
      assert json_response(ok, 200)["message"] == "confirmed"
    end
  end

  describe "account self-service" do
    setup %{conn: conn} do
      insert(:tenant, slug: "acme")

      resp =
        conn
        |> host("acme")
        |> json_post("/api/portal/registrations", registration("dana@example.com"))

      assert json_response(resp, 201)
      %{conn: ConnTest.recycle(resp)}
    end

    test "updates the profile, email, password, and preferences", %{conn: conn} do
      updated =
        conn |> host("acme") |> json_patch("/api/portal/account", %{first_name: "Danielle"})

      assert json_response(updated, 200)["customer_user"]["first_name"] == "Danielle"

      email =
        conn
        |> host("acme")
        |> json_patch("/api/portal/account/email", %{email: "new@example.com"})

      assert json_response(email, 200)["customer_user"]["confirmed"] == false
      assert json_response(email, 200)["customer_user"]["email"] == "new@example.com"

      password =
        conn
        |> host("acme")
        |> json_put("/api/portal/account/password", %{password: "an even longer password"})

      assert json_response(password, 200)["customer_user"]["email"] == "new@example.com"

      prefs = conn |> host("acme") |> get("/api/portal/account/notification_preferences")
      assert json_response(prefs, 200)["transactional"] == true

      updated_prefs =
        conn
        |> host("acme")
        |> json_patch("/api/portal/account/notification_preferences", %{marketing_opt_in: true})

      assert json_response(updated_prefs, 200)["marketing_opt_in"] == true
    end

    test "anonymous callers cannot reach the account" do
      resp = build_conn() |> host("acme") |> get("/api/portal/account")
      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "household invitations over HTTP" do
    test "invites and accepts a new adult, who then shares the household", %{conn: conn} do
      insert(:tenant, slug: "acme")

      signup =
        conn
        |> host("acme")
        |> json_post("/api/portal/registrations", registration("parent@example.com"))

      assert json_response(signup, 201)
      parent = ConnTest.recycle(signup)

      invited =
        parent
        |> host("acme")
        |> json_post("/api/portal/household/invites", %{
          email: "co@example.com",
          relationship: "parent"
        })

      assert %{"invite" => %{"email" => "co@example.com"}, "token" => token} =
               json_response(invited, 201)

      # The invitee can inspect the invite without a session.
      show = build_conn() |> host("acme") |> get("/api/portal/household_invites/#{token}")
      assert json_response(show, 200)["email"] == "co@example.com"

      accept =
        build_conn()
        |> host("acme")
        |> json_post(
          "/api/portal/household_invites/#{token}/accept",
          registration("co@example.com")
        )

      assert %{"member" => %{"role" => "manager"}} = json_response(accept, 201)

      household = ConnTest.recycle(accept) |> host("acme") |> get("/api/portal/household")
      assert length(json_response(household, 200)["members"]) == 2
    end

    test "a removed manager loses access immediately", %{conn: conn} do
      insert(:tenant, slug: "acme")

      signup =
        conn
        |> host("acme")
        |> json_post("/api/portal/registrations", registration("parent@example.com"))

      parent = ConnTest.recycle(signup)

      invited =
        parent
        |> host("acme")
        |> json_post("/api/portal/household/invites", %{email: "co@example.com"})

      assert %{"token" => token} = json_response(invited, 201)

      accept =
        build_conn()
        |> host("acme")
        |> json_post(
          "/api/portal/household_invites/#{token}/accept",
          registration("co@example.com")
        )

      assert json_response(accept, 201)
      co = ConnTest.recycle(accept)

      household = parent |> host("acme") |> get("/api/portal/household")
      members = json_response(household, 200)["members"]
      co_member = Enum.find(members, &(&1["customer_user"]["email"] == "co@example.com"))

      removed =
        parent |> host("acme") |> delete("/api/portal/household/members/#{co_member["id"]}")

      assert response(removed, 204)

      denied = co |> host("acme") |> get("/api/portal/household")
      assert json_response(denied, 403)["error"]["code"] == "forbidden"
    end
  end
end
