defmodule SportsCoachBookings.Notifications.Broadcasts.SegmentTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Notifications.Broadcasts.Segment

  test "an empty segment means all households" do
    assert Segment.empty?(Segment.normalize(nil))
    assert Segment.empty?(Segment.normalize(%{}))
    assert Segment.normalize(%{"all" => true}) == Segment.empty()
  end

  test "normalizes a conditions list to canonical string-keyed form" do
    segment = %{"match" => "all", "conditions" => [%{"type" => "package", "package_id" => "p1"}]}

    assert {:ok, normalized} = Segment.validate(segment)
    assert normalized["match"] == "all"
    assert [%{"type" => "package", "package_id" => "p1"}] = normalized["conditions"]
  end

  test "accepts a bare single condition" do
    assert {:ok, %{"conditions" => [%{"type" => "bookings"}]}} =
             Segment.validate(%{"type" => "bookings"})
  end

  test "rejects unknown condition types" do
    assert {:error, {:invalid_segment, message}} = Segment.validate(%{"type" => "nope"})
    assert message =~ "unknown condition type"
  end

  test "rejects an invalid match mode" do
    assert {:error, {:invalid_segment, _}} =
             Segment.validate(%{"match" => "some", "conditions" => []})
  end

  test "player_age requires min or max" do
    assert {:error, {:invalid_segment, _}} =
             Segment.validate(%{"type" => "player_age"})

    assert {:ok, _} = Segment.validate(%{"type" => "player_age", "min" => 7, "max" => 10})
  end

  test "package requires a package_id" do
    assert {:error, {:invalid_segment, _}} = Segment.validate(%{"type" => "package"})
    assert {:ok, _} = Segment.validate(%{"type" => "package", "package_id" => "p1"})
  end

  test "operational_booking_based? is true only with a bookings condition" do
    assert Segment.operational_booking_based?(%{"type" => "bookings"})
    refute Segment.operational_booking_based?(%{"type" => "package", "package_id" => "p"})
    refute Segment.operational_booking_based?(Segment.empty())
  end
end
