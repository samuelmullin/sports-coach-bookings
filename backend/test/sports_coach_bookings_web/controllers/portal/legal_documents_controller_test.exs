defmodule SportsCoachBookingsWeb.Portal.Legal.DocumentsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Legal
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  defp publish(kind, title, body) do
    {:ok, document} =
      Legal.publish_document(nil, %{"kind" => kind, "title" => title, "body_markdown" => body})

    document
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  defp notification_jobs do
    Repo.all(Oban.Job) |> Enum.filter(&(&1.queue == "notifications"))
  end

  describe "GET /api/portal/documents" do
    test "lists the active documents", %{conn: conn, tenant: tenant} do
      publish("terms", "Terms of Service", "# Terms")
      publish("privacy", "Privacy Policy", "# Privacy")
      # A superseded version must not appear.
      {:ok, _v2} =
        Legal.publish_document(nil, %{
          "kind" => "terms",
          "title" => "Terms v2",
          "body_markdown" => "# Terms v2"
        })

      body =
        conn
        |> with_host(tenant.slug)
        |> get("/api/portal/documents")
        |> json_response(200)

      kinds = Enum.map(body["data"], & &1["kind"]) |> Enum.sort()
      assert kinds == ["privacy", "terms"]

      assert [%{"title" => "Terms v2", "version" => 2}] =
               Enum.filter(body["data"], &(&1["kind"] == "terms"))
    end

    test "is empty when the tenant has no documents", %{conn: conn, tenant: tenant} do
      body = conn |> with_host(tenant.slug) |> get("/api/portal/documents") |> json_response(200)
      assert body["data"] == []
    end
  end

  describe "GET /api/portal/documents/:kind" do
    test "returns the active body", %{conn: conn, tenant: tenant} do
      publish("terms", "Terms of Service", "# Terms\n\nBe kind.")

      body =
        conn
        |> with_host(tenant.slug)
        |> get("/api/portal/documents/terms")
        |> json_response(200)

      assert body["kind"] == "terms"
      assert body["title"] == "Terms of Service"
      assert body["body_markdown"] == "# Terms\n\nBe kind."
      assert body["version"] == 1
      assert body["active"]
    end

    test "404s for an unknown kind", %{conn: conn, tenant: tenant} do
      resp = conn |> with_host(tenant.slug) |> get("/api/portal/documents/cookies")
      assert json_response(resp, 404)["error"]["code"] == "not_found"
    end
  end

  describe "POST /api/portal/documents/:kind/email" do
    test "queues exactly one message for the requested address", %{conn: conn, tenant: tenant} do
      publish("terms", "Terms of Service", "# Terms\n\nBe kind.")

      body =
        conn
        |> with_host(tenant.slug)
        |> json_post("/api/portal/documents/terms/email", %{"email" => "dana@example.com"})
        |> json_response(202)

      assert body == %{"status" => "queued", "email" => "dana@example.com"}

      assert Repo.aggregate(Message, :count) == 1
      assert [%Delivery{email: "dana@example.com", status: :queued}] = Repo.all(Delivery)
      assert [%{template_key: "legal_document", subject: "Terms of Service"}] = Repo.all(Message)
      assert length(notification_jobs()) == 1
    end

    test "rejects an invalid email", %{conn: conn, tenant: tenant} do
      publish("terms", "Terms of Service", "# Terms")

      resp =
        conn
        |> with_host(tenant.slug)
        |> json_post("/api/portal/documents/terms/email", %{"email" => "not-an-email"})

      assert json_response(resp, 422)["error"]["code"] == "invalid_email"
      assert Repo.aggregate(Message, :count) == 0
    end

    test "404s when no active document of that kind exists", %{conn: conn, tenant: tenant} do
      resp =
        conn
        |> with_host(tenant.slug)
        |> json_post("/api/portal/documents/privacy/email", %{"email" => "dana@example.com"})

      assert json_response(resp, 404)["error"]["code"] == "not_found"
    end
  end
end
