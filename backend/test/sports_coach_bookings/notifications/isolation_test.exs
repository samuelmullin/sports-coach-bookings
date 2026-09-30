defmodule SportsCoachBookings.Notifications.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Notifications.{
    Delivery,
    Message,
    NotificationPreference,
    Suppression
  }

  test "messages are tenant-isolated" do
    assert_tenant_isolated(Message, :message)
  end

  test "deliveries are tenant-isolated" do
    assert_tenant_isolated(Delivery, :delivery)
  end

  test "suppressions are tenant-isolated" do
    assert_tenant_isolated(Suppression, :suppression)
  end

  test "notification preferences are tenant-isolated" do
    assert_tenant_isolated(NotificationPreference, :notification_preference)
  end
end
