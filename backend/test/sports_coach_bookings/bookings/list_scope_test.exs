defmodule SportsCoachBookings.Bookings.ListScopeTest do
  @moduledoc """
  `Bookings.list_for_household/2` scopes: `:upcoming` is "session still ahead and
  active"; `:past` is "session finished or terminal booking". A cancelled booking
  for a future session belongs under `:past` (it was shown as "upcoming" before).
  """

  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Bookings

  setup do
    tenant = insert(:tenant, slug: "scope-#{System.unique_integer([:positive])}")
    put_tenant(tenant)
    %{household: insert(:household).id}
  end

  defp session_at(offset_hours) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(offset_hours * 3600, :second)
      |> DateTime.truncate(:microsecond)

    insert(:session, starts_at: starts_at, ends_at: DateTime.add(starts_at, 3600, :second))
  end

  defp booking(household, session, status) do
    insert(:booking, household_id: household, session_id: session.id, status: status)
  end

  defp ids(rows), do: rows |> Enum.map(& &1.booking.id) |> Enum.sort()

  test "upcoming holds live bookings for future sessions only; past holds the rest", %{
    household: household
  } do
    live = booking(household, session_at(48), :confirmed)
    held = booking(household, session_at(72), :held)
    cancelled_future = booking(household, session_at(96), :cancelled)
    finished = booking(household, session_at(-48), :attended)
    confirmed_but_over = booking(household, session_at(-24), :confirmed)

    upcoming = Bookings.list_for_household(household, scope: :upcoming)
    past = Bookings.list_for_household(household, scope: :past)

    assert ids(upcoming) == Enum.sort([live.id, held.id])
    assert ids(past) == Enum.sort([cancelled_future.id, finished.id, confirmed_but_over.id])
    assert length(Bookings.list_for_household(household, scope: :all)) == 5
  end

  test "a booking is never in both scopes", %{household: household} do
    booking(household, session_at(48), :confirmed)
    booking(household, session_at(48), :cancelled)
    booking(household, session_at(-48), :confirmed)

    upcoming = ids(Bookings.list_for_household(household, scope: :upcoming))
    past = ids(Bookings.list_for_household(household, scope: :past))

    assert upcoming != []
    assert past != []
    assert MapSet.disjoint?(MapSet.new(upcoming), MapSet.new(past))
  end
end
