defmodule SportsCoachBookings.Security.RateLimitTest do
  @moduledoc """
  WP-19 rate limiting: unit tests for the ETS limiter and an end-to-end test of
  the plug on an unauthenticated auth endpoint.
  """

  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.RateLimiter

  setup do
    RateLimiter.reset()
    previous = Application.get_env(:sports_coach_bookings, :rate_limiting_enabled, false)

    on_exit(fn ->
      Application.put_env(:sports_coach_bookings, :rate_limiting_enabled, previous)
      RateLimiter.reset()
    end)

    :ok
  end

  describe "RateLimiter.hit/3" do
    test "allows up to the limit and then denies with a retry window" do
      assert RateLimiter.hit(["ip:1.2.3.4"], 3, 60) == :ok
      assert RateLimiter.hit(["ip:1.2.3.4"], 3, 60) == :ok
      assert RateLimiter.hit(["ip:1.2.3.4"], 3, 60) == :ok
      assert {:error, retry_after} = RateLimiter.hit(["ip:1.2.3.4"], 3, 60)
      assert retry_after in 1..60
    end

    test "keys are independent" do
      assert RateLimiter.hit(["ip:a"], 1, 60) == :ok
      assert {:error, _} = RateLimiter.hit(["ip:a"], 1, 60)
      assert RateLimiter.hit(["ip:b"], 1, 60) == :ok
    end

    test "a request is denied when any key is over its limit" do
      assert RateLimiter.hit(["ip:full"], 1, 60) == :ok
      assert {:error, _} = RateLimiter.hit(["ip:full", "acct:fresh@example.com"], 1, 60)
    end

    test "reset clears the counters" do
      assert RateLimiter.hit(["ip:x"], 1, 60) == :ok
      RateLimiter.reset()
      assert RateLimiter.hit(["ip:x"], 1, 60) == :ok
    end
  end

  describe "the plug on POST /api/platform/password_reset (limit 30/min)" do
    test "returns 429 once the per-IP limit is exceeded", %{conn: conn} do
      Application.put_env(:sports_coach_bookings, :rate_limiting_enabled, true)

      for _ <- 1..30 do
        conn
        |> post(~p"/api/platform/password_reset", %{email: "nobody@example.com"})
        |> response(202)
      end

      response =
        post(conn, ~p"/api/platform/password_reset", %{email: "nobody@example.com"})

      assert response.status == 429
      assert json_response(response, 429)["error"]["code"] == "too_many_requests"
      assert get_resp_header(response, "retry-after") != []
    end

    test "another IP is unaffected once one is blocked", %{conn: conn} do
      Application.put_env(:sports_coach_bookings, :rate_limiting_enabled, true)

      for _ <- 1..30 do
        conn
        |> put_req_header("fly-client-ip", "203.0.113.7")
        |> post(~p"/api/platform/password_reset", %{email: "a@example.com"})
        |> response(202)
      end

      blocked =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.7")
        |> post(~p"/api/platform/password_reset", %{email: "a@example.com"})

      assert blocked.status == 429

      fresh =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.8")
        |> post(~p"/api/platform/password_reset", %{email: "b@example.com"})

      assert fresh.status == 202
    end
  end
end
