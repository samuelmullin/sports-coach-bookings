defmodule SportsCoachBookingsWeb.Staff.Legal.DocumentsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Legal

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  test "an owner publishes a new version", %{conn: conn, tenant: tenant} do
    body =
      conn
      |> staff_conn(tenant, :owner)
      |> json_post("/api/staff/legal_documents", %{
        "document" => %{
          "kind" => "terms",
          "title" => "Terms of Service",
          "body_markdown" => "# Terms"
        }
      })
      |> json_response(201)

    assert body["kind"] == "terms"
    assert body["version"] == 1
    assert body["active"]

    assert {:ok, active} = Legal.active_document("terms")
    assert active.id == body["id"]
  end

  test "an admin publishes a superseding version", %{conn: conn, tenant: tenant} do
    {:ok, _v1} =
      Legal.publish_document(nil, %{"kind" => "terms", "title" => "A", "body_markdown" => "A"})

    body =
      conn
      |> staff_conn(tenant, :admin)
      |> json_post("/api/staff/legal_documents", %{
        "kind" => "terms",
        "title" => "B",
        "body_markdown" => "B"
      })
      |> json_response(201)

    assert body["version"] == 2
    assert body["active"]
  end

  test "a coach cannot publish", %{conn: conn, tenant: tenant} do
    resp =
      conn
      |> staff_conn(tenant, :coach)
      |> json_post("/api/staff/legal_documents", %{
        "kind" => "terms",
        "title" => "Nope",
        "body_markdown" => "Nope"
      })

    assert json_response(resp, 403)["error"]["code"] == "forbidden"
    assert Legal.list_documents("terms") == []
  end

  test "an owner lists versions", %{conn: conn, tenant: tenant} do
    {:ok, _v1} =
      Legal.publish_document(nil, %{"kind" => "terms", "title" => "A", "body_markdown" => "A"})

    {:ok, _v2} =
      Legal.publish_document(nil, %{"kind" => "terms", "title" => "B", "body_markdown" => "B"})

    body =
      conn
      |> staff_conn(tenant, :owner)
      |> get("/api/staff/legal_documents?kind=terms")
      |> json_response(200)

    assert Enum.map(body["data"], & &1["version"]) == [2, 1]
  end

  test "a coach may read the list", %{conn: conn, tenant: tenant} do
    {:ok, _v1} =
      Legal.publish_document(nil, %{"kind" => "terms", "title" => "A", "body_markdown" => "A"})

    body =
      conn
      |> staff_conn(tenant, :coach)
      |> get("/api/staff/legal_documents")
      |> json_response(200)

    assert length(body["data"]) == 1
  end
end
