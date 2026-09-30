defmodule SportsCoachBookingsWeb.SpaControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  describe "portal SPA" do
    test "GET / does not crash when there is no path param", %{conn: conn} do
      conn = get(conn, "/")

      refute conn.status == 500

      # When the bundle is present it must be served as HTML, otherwise
      # `x-content-type-options: nosniff` makes the browser show raw source.
      if conn.status == 200 do
        assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      end
    end

    test "returns 503 frontend_not_built when the bundle is absent", %{conn: conn} do
      previous = Application.get_env(:sports_coach_bookings, :repo_root)
      Application.put_env(:sports_coach_bookings, :repo_root, System.tmp_dir!())
      on_exit(fn -> Application.put_env(:sports_coach_bookings, :repo_root, previous) end)

      conn = get(conn, "/")

      assert conn.status == 503
      assert json_response(conn, 503)["error"]["code"] == "frontend_not_built"
    end
  end

  describe "admin SPA" do
    test "GET /admin/ does not crash", %{conn: conn} do
      conn = get(conn, "/admin/")

      refute conn.status == 500
    end
  end
end
