defmodule SportsCoachBookings.Security.OpenRedirectTest do
  @moduledoc "WP-19: provider return/refresh URLs cannot redirect off-site."

  use ExUnit.Case, async: false

  alias SportsCoachBookingsWeb.SafeRedirect

  setup do
    previous = Application.get_env(:sports_coach_bookings, :base_domain)
    Application.put_env(:sports_coach_bookings, :base_domain, "sportscoachbookings.com")
    on_exit(fn -> Application.put_env(:sports_coach_bookings, :base_domain, previous) end)
    :ok
  end

  test "allows the configured base domain and its subdomains" do
    assert SafeRedirect.sanitize("https://sportscoachbookings.com/admin/payments")
    assert SafeRedirect.sanitize("https://acme.sportscoachbookings.com/admin/payments")
  end

  test "allows http(s) localhost for development" do
    assert SafeRedirect.sanitize("http://localhost:4000/admin/payments")
    assert SafeRedirect.sanitize("http://127.0.0.1:4000/x")
  end

  test "rejects off-site hosts" do
    assert SafeRedirect.sanitize("https://evil.example/steal") == nil
    assert SafeRedirect.sanitize("https://sportscoachbookings.com.evil.example/") == nil
  end

  test "rejects non-http schemes and relative/garbage values" do
    assert SafeRedirect.sanitize("javascript:alert(1)") == nil
    assert SafeRedirect.sanitize("//evil.example/x") == nil
    assert SafeRedirect.sanitize("not a url") == nil
    assert SafeRedirect.sanitize(nil) == nil
  end

  test "rejects plain http on a non-local host" do
    assert SafeRedirect.sanitize("http://sportscoachbookings.com/admin") == nil
  end
end
