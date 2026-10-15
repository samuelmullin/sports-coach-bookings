defmodule SportsCoachBookings.Websites.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Websites.ContactSubmission
  alias SportsCoachBookings.Websites.Site

  test "sites are tenant-isolated", do: assert_tenant_isolated(Site, :website_site)

  test "contact submissions are tenant-isolated",
    do: assert_tenant_isolated(ContactSubmission, :website_contact_submission)
end
