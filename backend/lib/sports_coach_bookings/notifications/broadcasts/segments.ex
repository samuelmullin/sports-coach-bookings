defmodule SportsCoachBookings.Notifications.Broadcasts.Segments do
  @moduledoc """
  Resolves a broadcast `Segment` to a de-duplicated list of recipient manager
  emails.

  Resolution goes through the **public** query functions of the owning contexts
  (`Customers`, `Bookings`, `Scheduling`, `Players`, `Credits`, `Commerce`) — it
  never reads another context's tables directly. Conditions are resolved to sets
  of household ids and then AND/OR-combined; the resulting households are mapped
  to their active customer-user managers, de-duplicated by email.

  Marketing recipients are additionally filtered for CASL: addresses without
  `marketing_opt_in` and suppressed addresses are dropped. Operational and
  transactional recipients are not filtered here (the engine still suppresses
  hard-bounced/complained addresses at delivery time).
  """

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Notifications.Broadcasts.Segment
  alias SportsCoachBookings.Notifications.Preferences
  alias SportsCoachBookings.Notifications.Suppressions
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Scheduling

  @page_limit 100
  @wide_from ~U[2000-01-01 00:00:00.000000Z]
  @wide_days 3_650

  @type recipient :: %{
          type: :customer_user | :email,
          id: binary() | nil,
          email: String.t(),
          household_id: binary() | nil
        }

  @doc "Resolves the segment to the set of household ids it matches."
  @spec household_ids(term()) :: MapSet.t()
  def household_ids(segment) do
    canonical = Segment.normalize(segment)
    conditions = Map.get(canonical, "conditions", [])

    case {Map.get(canonical, "match", "all"), conditions} do
      {"all", []} -> all_household_ids()
      {_match, []} -> MapSet.new()
      {"all", conditions} -> conditions |> Enum.map(&ids_for/1) |> intersect()
      {"any", conditions} -> conditions |> Enum.map(&ids_for/1) |> union()
      _ -> MapSet.new()
    end
  end

  @doc "Resolves the segment to de-duplicated recipient maps for `category`."
  @spec recipients(term(), atom()) :: [recipient()]
  def recipients(segment, category) do
    segment
    |> household_ids()
    |> Enum.flat_map(&managers_for_household/1)
    |> dedupe_by_email()
    |> maybe_filter_marketing(category)
  end

  @doc "The number of recipients `recipients/2` would return."
  @spec recipient_count(term(), atom()) :: non_neg_integer()
  def recipient_count(segment, category), do: segment |> recipients(category) |> length()

  ## Household-id resolution per condition type

  defp ids_for(%{"type" => "bookings"} = condition), do: booking_ids(condition)

  defp ids_for(%{"type" => "player_age"} = condition), do: player_age_ids(condition)

  defp ids_for(%{"type" => "credits"} = condition), do: credits_ids(condition)

  defp ids_for(%{"type" => "package"} = condition), do: package_ids(condition)

  defp ids_for(_condition), do: MapSet.new()

  defp booking_ids(condition) do
    status = normalize_status(fetch(condition, "status") || "confirmed")
    scope = session_scope(condition)

    status
    |> all_bookings()
    |> Enum.filter(fn booking -> scope == :all or MapSet.member?(scope, booking.session_id) end)
    |> Enum.map(& &1.household_id)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp player_age_ids(condition) do
    min = to_integer(fetch(condition, "min"))
    max = to_integer(fetch(condition, "max"))
    today = Date.utc_today()

    Players.search(nil)
    |> Enum.filter(fn player ->
      player.date_of_birth != nil and age_in_range?(player, today, min, max)
    end)
    |> Enum.map(& &1.household_id)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp age_in_range?(player, today, min, max) do
    age = Players.age_on(player, today)
    (is_nil(min) or age >= min) and (is_nil(max) or age <= max)
  end

  defp credits_ids(condition) do
    min_balance = to_integer(fetch(condition, "min_balance")) || 1
    expiring_before = parse_datetime(fetch(condition, "expiring_before"))

    Customers.list_households()
    |> Enum.filter(fn household ->
      balance_ok?(household.id, min_balance) and expiring_ok?(household.id, expiring_before)
    end)
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp package_ids(condition) do
    package_id = fetch(condition, "package_id")

    :package
    |> all_orders()
    |> Enum.filter(fn order ->
      Enum.any?(order.lines, fn line ->
        line.type == :package and line.ref_id == package_id
      end)
    end)
    |> Enum.map(& &1.household_id)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  ## Session scoping

  defp session_scope(condition) do
    sets =
      [
        maybe_set(fetch(condition, "session_ids")),
        offering_sessions(fetch(condition, "offering_ids")),
        venue_sessions(fetch(condition, "venue_id")),
        range_sessions(fetch(condition, "from"), fetch(condition, "to"))
      ]
      |> Enum.reject(&is_nil/1)

    case sets do
      [] -> :all
      [set | rest] -> Enum.reduce(rest, set, &MapSet.intersection/2)
    end
  end

  defp maybe_set(nil), do: nil
  defp maybe_set([]), do: nil
  defp maybe_set(ids) when is_list(ids), do: MapSet.new(ids)
  defp maybe_set(_), do: nil

  defp offering_sessions(nil), do: nil
  defp offering_sessions([]), do: nil

  defp offering_sessions(offering_ids) when is_list(offering_ids) do
    offering_ids
    |> Enum.map(fn offering_id ->
      sessions_for(%{offering_id: offering_id})
    end)
    |> union_or_nil()
  end

  defp offering_sessions(_), do: nil

  defp venue_sessions(nil), do: nil

  defp venue_sessions(venue_id) when is_binary(venue_id) do
    sessions_for(%{venue_id: venue_id})
  end

  defp venue_sessions(_), do: nil

  defp range_sessions(nil, nil), do: nil

  defp range_sessions(from, to) do
    sessions_for(%{
      from: parse_datetime(from) || @wide_from,
      to: parse_datetime(to) || DateTime.add(DateTime.utc_now(), @wide_days, :day)
    })
  end

  defp sessions_for(filters) do
    filters
    |> Map.put_new(:from, @wide_from)
    |> Map.put_new(:to, DateTime.add(DateTime.utc_now(), @wide_days, :day))
    |> Scheduling.list_sessions()
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp union_or_nil([]), do: nil
  defp union_or_nil(sets), do: Enum.reduce(sets, MapSet.new(), &MapSet.union/2)

  ## Bookings / orders pagination

  defp all_bookings(status), do: page_bookings(status, nil, [])

  defp page_bookings(status, cursor, acc) do
    params = page_params(cursor)
    %{data: rows, next_cursor: next} = Bookings.page_bookings(%{status: status}, params)
    acc = acc ++ Enum.map(rows, & &1.booking)

    if next, do: page_bookings(status, next, acc), else: acc
  end

  defp all_orders(type), do: page_orders(type, nil, [])

  defp page_orders(type, cursor, acc) do
    params = page_params(cursor)
    filters = %{type: type, status: :paid}
    %{data: rows, next_cursor: next} = Commerce.page_orders(filters, params)
    acc = acc ++ rows

    if next, do: page_orders(type, next, acc), else: acc
  end

  defp page_params(nil), do: %{limit: @page_limit}
  defp page_params(cursor), do: %{limit: @page_limit, cursor: cursor}

  ## Households -> managers

  defp all_household_ids do
    Customers.list_households() |> Enum.map(& &1.id) |> MapSet.new()
  end

  defp managers_for_household(household_id) do
    household_id
    |> Customers.list_household_members()
    |> Enum.map(& &1.customer_user)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&CustomerUser.active?/1)
    |> Enum.map(fn user ->
      %{
        type: :customer_user,
        id: user.id,
        email: String.downcase(user.email),
        household_id: household_id
      }
    end)
  end

  defp dedupe_by_email(recipients) do
    recipients
    |> Enum.uniq_by(& &1.email)
    |> Enum.sort_by(& &1.email)
  end

  defp maybe_filter_marketing(recipients, :marketing) do
    Enum.filter(recipients, &marketing_allowed?/1)
  end

  defp maybe_filter_marketing(recipients, _category), do: recipients

  defp marketing_allowed?(recipient) do
    not Suppressions.suppressed?(nil, recipient.email) and
      Preferences.allowed?(%{type: :customer_user, id: recipient.id}, :marketing)
  end

  ## Helpers

  defp balance_ok?(household_id, min_balance) do
    household_id
    |> Credits.balance()
    |> Enum.sum_by(& &1.amount)
    |> Kernel.>=(min_balance)
  end

  defp expiring_ok?(_household_id, nil), do: true

  defp expiring_ok?(household_id, %DateTime{} = before) do
    household_id
    |> Credits.list_lots()
    |> Enum.any?(fn lot ->
      lot.remaining > 0 and lot.expires_at != nil and
        DateTime.compare(lot.expires_at, before) != :gt
    end)
  end

  defp intersect([set | rest]), do: Enum.reduce(rest, set, &MapSet.intersection/2)
  defp intersect([]), do: MapSet.new()

  defp union([set | rest]), do: Enum.reduce(rest, set, &MapSet.union/2)
  defp union([]), do: MapSet.new()

  defp normalize_status(:confirmed), do: :confirmed

  defp normalize_status(value) when is_binary(value) do
    Enum.find(Bookings.Booking.statuses(), :confirmed, &(Atom.to_string(&1) == value))
  end

  defp normalize_status(_), do: :confirmed

  defp to_integer(nil), do: nil
  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_integer(_), do: nil

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = value), do: value

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          {:error, _} -> nil
        end
    end
  end

  defp parse_datetime(_), do: nil

  defp fetch(map, key) when is_map(map), do: Map.get(map, key)
end
