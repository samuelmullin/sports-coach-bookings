defmodule SportsCoachBookingsWeb.HealthControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: true

  test "GET /health is a liveness probe", %{conn: conn} do
    conn = get(conn, "/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /health/ready reports the database check", %{conn: conn} do
    conn = get(conn, "/health/ready")

    assert %{"status" => "ok", "checks" => %{"database" => "ok"}} =
             json_response(conn, 200)
  end
end
