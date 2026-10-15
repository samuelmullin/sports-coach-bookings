defmodule SportsCoachBookings.Scheduling do
  @moduledoc """
  Sessions, session series, and the staff/portal calendars. Owned by WP-11.

  Admins publish concrete, bookable sessions (a single session or a materialised
  series); customers and coaches browse them with filters and live seat
  availability. Recurrence is DST-safe: occurrences are computed in the venue's
  local timezone (see `SportsCoachBookings.Scheduling.Recurrence`).

  All reads and writes are tenant-scoped: callers place the tenant in context
  (via `SportsCoachBookingsWeb.Plugs.ResolveTenant` in requests or
  `SportsCoachBookings.DataCase.put_tenant/1` in tests) and every function runs
  inside `SportsCoachBookings.Repo.with_tenant_tx/2` so RLS applies.

  The seat counters are written only through `SportsCoachBookings.Scheduling.Seats`
  (used by wp-14); this context never mutates `booked_count`/`held_count`.
  """

  import Ecto.Query

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling.Bookings
  alias SportsCoachBookings.Scheduling.Recurrence
  alias SportsCoachBookings.Scheduling.Session
  alias SportsCoachBookings.Scheduling.SessionCoach
  alias SportsCoachBookings.Scheduling.SessionSeries
  alias SportsCoachBookings.Staff

  @max_portal_range_days 62
  @default_range_days 62

  ## Session reads

  @doc "Fetches a session by id, raising if it does not exist for this tenant."
  @spec get_session!(binary()) :: Session.t()
  def get_session!(id), do: read(fn -> Repo.get!(Session, id) end)

  @doc "Fetches a session by id, returning `{:error, :not_found}` when absent."
  @spec fetch_session(binary()) :: {:ok, Session.t()} | {:error, :not_found}
  def fetch_session(id), do: read(fn -> fetch_record(Session, id) end)

  @doc """
  Session detail for the staff view, including seats/availability and the
  roster.

  The roster is composed from `Bookings.session_roster/1` when wp-14 exports it,
  and is an empty list until then.
  """
  @spec session_detail(binary()) :: {:ok, map()} | {:error, :not_found}
  def session_detail(id) do
    read(fn ->
      with {:ok, session} <- fetch_record(Session, id) do
        session = Repo.preload(session, :session_coaches)
        [entry] = build_entries([session], [])
        {:ok, Map.put(entry, :roster, roster_for(session.id))}
      end
    end)
  end

  @doc "Fetches a series by id, raising if it does not exist for this tenant."
  @spec get_series!(binary()) :: SessionSeries.t()
  def get_series!(id), do: read(fn -> Repo.get!(SessionSeries, id) end)

  @doc "Fetches a series by id, returning `{:error, :not_found}` when absent."
  @spec fetch_series(binary()) :: {:ok, SessionSeries.t()} | {:error, :not_found}
  def fetch_series(id), do: read(fn -> fetch_record(SessionSeries, id) end)

  @doc """
  Lists sessions matching `filters`.

  Filters: `:from`, `:to` (UTC datetimes), `:venue_id`, `:offering_id`,
  `:coach_id` (membership), `:status`, `:visibility`. Ordered by `starts_at`.
  """
  @spec list_sessions(map() | keyword()) :: [Session.t()]
  def list_sessions(filters \\ %{}) do
    read(fn ->
      [from: from, to: to] = range(filters)

      Session
      |> where([s], s.starts_at >= ^from and s.starts_at <= ^to)
      |> filter_sessions(normalize(filters))
      |> order_by([s], asc: s.starts_at)
      |> Repo.all()
    end)
  end

  @doc "Paginates sessions newest-first. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_sessions(map() | keyword(), map() | keyword()) ::
          %{data: [Session.t()], next_cursor: binary() | nil}
  def page_sessions(filters \\ %{}, params \\ %{}) do
    read(fn ->
      query = Session |> filter_sessions(normalize(filters))
      {rows, cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  ## Calendar

  @doc """
  Returns calendar entries for the staff view.

  Options: `include_hidden: true` to include hidden (staff-only) sessions;
  `player: %Players.Player{}` to filter by age eligibility and flag
  `already_booked`.
  """
  @spec calendar(map() | keyword(), keyword()) :: [map()]
  def calendar(filters \\ %{}, opts \\ []) do
    read(fn -> do_calendar(filters, opts) end)
  end

  @doc """
  Returns upcoming, public, bookable sessions for the portal.

  A range is required and may not exceed #{@max_portal_range_days} days.
  """
  @spec portal_sessions(map() | keyword(), keyword()) :: [map()] | {:error, term()}
  def portal_sessions(filters \\ %{}, opts \\ []) do
    read(fn ->
      case portal_range(filters) do
        {:error, reason} ->
          {:error, reason}

        {from, to} ->
          opts =
            opts
            |> Keyword.put_new(:from, from)
            |> Keyword.put_new(:to, to)
            |> Keyword.put(:portal, true)

          do_calendar(Map.merge(normalize(filters), %{"from" => from, "to" => to}), opts)
      end
    end)
  end

  @doc """
  Returns a single publicly bookable session for the portal.

  Returns `{:error, :not_found}` when the session is missing, cancelled, or not
  public, so the portal cannot use this to probe non-public sessions.
  """
  @spec portal_session(binary(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def portal_session(id, opts \\ []) do
    read(fn ->
      with {:ok, session} <- fetch_record(Session, id),
           true <- session.status == :scheduled and session.visibility == :public,
           true <- portal_session_visible?(session, opts) do
        session = Repo.preload(session, :session_coaches)
        [entry] = build_entries([session], Keyword.put(opts, :portal, true))
        {:ok, entry}
      else
        _ -> {:error, :not_found}
      end
    end)
  end

  @doc "Calendar entries for sessions assigned to `membership_id`."
  @spec my_sessions(binary(), map() | keyword(), keyword()) :: [map()]
  def my_sessions(membership_id, filters \\ %{}, opts \\ []) do
    read(fn ->
      [from: from, to: to] = range(filters)

      sessions =
        Session
        |> join(:inner, [s], sc in SessionCoach,
          on: sc.session_id == s.id and sc.membership_id == ^membership_id
        )
        |> where([s], s.starts_at >= ^from and s.starts_at <= ^to)
        |> where([s], s.status != :cancelled)
        |> order_by([s], asc: s.starts_at)
        |> Repo.all()
        |> Repo.preload(:session_coaches)

      build_entries(sessions, opts)
    end)
  end

  ## Session writes

  @doc """
  Creates a single session.

  `attrs` accepts `:offering_id`, `:venue_id`, `:starts_at`, `:ends_at`
  (defaults to `starts_at + offering.duration_minutes`), `:capacity` (defaults
  to `offering.default_capacity`), `:visibility`, `:title_override`,
  `:notes_public`, `:notes_staff`, and `:coach_ids`.

  Returns `{:ok, %{session: session, warnings: warnings}}`; coach/venue
  double-bookings are warnings, not errors.
  """
  @spec create_session(map(), map() | keyword()) ::
          {:ok, %{session: Session.t(), warnings: [map()]}} | {:error, term()}
  def create_session(actor, attrs) do
    attrs = normalize(attrs)

    read(fn ->
      with {:ok, offering} <- Catalog.fetch_offering(get_attr(attrs, :offering_id)),
           {:ok, venue} <- Catalog.fetch_venue(get_attr(attrs, :venue_id)),
           {:ok, session} <- insert_session(attrs, offering, venue, nil),
           {:ok, _coaches} <- put_coaches(session, coach_ids(attrs)),
           {:ok, session} <- reload_session(session),
           {:ok, _audit} <- Audit.record(actor, "scheduling.session.created", session, %{}) do
        {:ok, %{session: session, warnings: detect_for_sessions([session])}}
      end
    end)
  end

  @doc """
  Creates a session series and materialises every occurrence.

  Combines the recurrence fields (`:weekdays`, `:start_time_local`,
  `:duration_minutes`, `:starts_on`, `:ends_on`, `:timezone`) with the session
  template fields. At most `Recurrence.max_occurrences/0` sessions per request.
  """
  @spec create_series(map(), map() | keyword()) ::
          {:ok, %{series: SessionSeries.t(), sessions: [Session.t()], warnings: [map()]}}
          | {:error, term()}
  def create_series(actor, attrs) do
    attrs = normalize(attrs)

    read(fn ->
      with {:ok, offering} <- Catalog.fetch_offering(get_attr(attrs, :offering_id)),
           {:ok, venue} <- Catalog.fetch_venue(get_attr(attrs, :venue_id)),
           {:ok, series} <- insert_series(attrs, venue),
           {:ok, occurrences} <- Recurrence.occurrences(series),
           {:ok, sessions} <- insert_occurrences(series, occurrences, attrs, offering, venue),
           {:ok, _audit} <-
             Audit.record(actor, "scheduling.series.created", series, %{
               session_count: length(sessions)
             }) do
        {:ok,
         %{
           series: series,
           sessions: sessions,
           warnings: detect_for_sessions(sessions)
         }}
      end
    end)
  end

  @doc """
  Updates a single session (notes, capacity, visibility, time, venue, coaches).

  Reducing capacity below the confirmed + held bookings returns
  `{:error, {:capacity_below_bookings, count}}`. If the start time or venue
  changes on a session that has bookings, `session.rescheduled` is published.
  """
  @spec update_session(map(), binary(), map() | keyword(), keyword()) ::
          {:ok, %{session: Session.t(), warnings: [map()]}} | {:error, term()}
  def update_session(actor, id, attrs, _opts \\ []) do
    attrs = normalize(attrs)

    read(fn ->
      with {:ok, session} <- fetch_record(Session, id),
           :ok <- guard_single_update(session, attrs),
           {:ok, updated} <- do_update_session(session, attrs),
           {:ok, updated} <- reload_session(updated),
           {:ok, _} <- maybe_publish_rescheduled(session, updated),
           {:ok, _audit} <- Audit.record(actor, "scheduling.session.updated", updated, %{}) do
        {:ok, %{session: updated, warnings: detect_for_sessions([updated])}}
      end
    end)
  end

  @doc """
  Reschedules a session (time and/or venue).

  Delegates to `update_session/4`; `session.rescheduled` is published when the
  session already has bookings.
  """
  @spec reschedule_session(map(), binary(), map() | keyword()) ::
          {:ok, %{session: Session.t(), warnings: [map()]}} | {:error, term()}
  def reschedule_session(actor, id, attrs), do: update_session(actor, id, attrs, [])

  @doc """
  Cancels a session, publishing `session.cancelled`.

  Returns the impact (`booked_count` + `held_count`) so the caller can report how
  many bookings wp-14 must release/refund under the provider-cancelled rules.
  """
  @spec cancel_session(map(), binary(), binary() | nil) ::
          {:ok, %{session: Session.t(), impact: map()}} | {:error, term()}
  def cancel_session(actor, id, reason \\ nil) do
    read(fn -> do_cancel(actor, id, reason) end)
  end

  defp do_cancel(actor, id, reason) do
    with {:ok, session} <- fetch_record(Session, id) do
      if session.status == :cancelled do
        {:ok, %{session: session, impact: impact(session)}}
      else
        do_cancel_session(actor, session, reason)
      end
    end
  end

  @doc """
  Marks every past, still-scheduled session as `:completed`. Used by the nightly
  job; `now` is injectable for tests.
  """
  @spec mark_completed(DateTime.t()) :: {:ok, non_neg_integer()}
  def mark_completed(now \\ DateTime.utc_now()) do
    read(fn ->
      {count, _} =
        Repo.update_all(
          from(s in Session, where: s.status == :scheduled and s.ends_at < ^now),
          set: [status: :completed, updated_at: now]
        )

      {:ok, count}
    end)
  end

  ## Series edits

  @doc """
  Edits a session series.

  `scope` is `:single` (one occurrence; `target_id` is a session id),
  `:following` (that occurrence and all later ones; `target_id` is a session
  id), or `:all` (every occurrence; `target_id` is a series id).

  Editing occurrences that already have bookings requires `confirm: true`,
  otherwise `{:error, {:bookings_exist, count}}` is returned. Changing
  `:start_time_local` keeps each occurrence's local date (DST-safe).
  """
  @spec update_series(map(), atom(), binary(), map() | keyword(), keyword()) ::
          {:ok, %{sessions: [Session.t()], series: SessionSeries.t() | nil, warnings: [map()]}}
          | {:error, term()}
  def update_series(actor, scope, target_id, attrs, opts \\ []) do
    attrs = normalize(attrs)

    read(fn ->
      with {:ok, target, targets} <- series_targets(scope, target_id),
           :ok <- guard_series_update(targets, attrs, opts),
           {:ok, series} <- maybe_update_series(target, scope, attrs),
           {:ok, updated} <- apply_series_edit(targets, attrs),
           {:ok, _audit} <-
             Audit.record(actor, "scheduling.series.updated", series, %{
               scope: scope,
               session_count: length(updated)
             }) do
        {:ok, %{sessions: updated, series: series, warnings: detect_for_sessions(updated)}}
      end
    end)
  end

  ## Private: creation

  defp insert_session(attrs, offering, venue, series_id) do
    starts_at = parse_datetime(get_attr(attrs, :starts_at))
    duration = get_attr(attrs, :duration_minutes) || offering.duration_minutes
    ends_at = parse_datetime(get_attr(attrs, :ends_at)) || default_ends_at(starts_at, duration)

    access_mode = get_attr(attrs, :access_mode) || default_access_mode(offering)

    capacity =
      get_attr(attrs, :capacity) ||
        mode_capacity(offering, access_mode)

    changeset =
      Session.create_changeset(%Session{}, %{
        tenant_id: TenantContext.get_tenant_id(),
        offering_id: offering.id,
        venue_id: venue.id,
        starts_at: starts_at,
        ends_at: ends_at,
        capacity: capacity,
        visibility: get_attr(attrs, :visibility) || :public,
        title_override: get_attr(attrs, :title_override),
        notes_public: get_attr(attrs, :notes_public),
        notes_staff: get_attr(attrs, :notes_staff),
        access_mode: access_mode,
        party_size: get_attr(attrs, :party_size),
        exclusive_household_id: get_attr(attrs, :exclusive_household_id),
        series_id: series_id
      })
      |> maybe_put_show_coaches(get_attr(attrs, :show_coaches))

    Repo.insert(changeset)
  end

  defp maybe_put_show_coaches(changeset, nil), do: changeset

  defp maybe_put_show_coaches(changeset, value),
    do: Ecto.Changeset.put_change(changeset, :show_coaches, value)

  defp default_ends_at(nil, _duration), do: nil
  defp default_ends_at(starts_at, duration), do: DateTime.add(starts_at, duration * 60)

  defp default_access_mode(%{public_enabled: false, private_enabled: true}), do: :private
  defp default_access_mode(_offering), do: :public

  defp mode_capacity(offering, mode) when mode in [:private, "private"] do
    if map_size(offering.private_price_tiers || %{}) == 0,
      do: offering.default_capacity,
      else: offering.private_max_players
  end

  defp mode_capacity(offering, _mode) do
    if map_size(offering.public_price_tiers || %{}) == 0,
      do: offering.default_capacity,
      else: offering.public_max_players
  end

  defp insert_series(attrs, venue) do
    changeset =
      SessionSeries.changeset(%SessionSeries{}, %{
        tenant_id: TenantContext.get_tenant_id(),
        weekdays: get_attr(attrs, :weekdays) || [],
        start_time_local: parse_time(get_attr(attrs, :start_time_local)),
        duration_minutes: get_attr(attrs, :duration_minutes),
        starts_on: parse_date(get_attr(attrs, :starts_on)),
        ends_on: parse_date(get_attr(attrs, :ends_on)),
        timezone: get_attr(attrs, :timezone) || venue.timezone,
        offering_id: get_attr(attrs, :offering_id),
        venue_id: get_attr(attrs, :venue_id)
      })

    Repo.insert(changeset)
  end

  defp insert_occurrences(series, occurrences, attrs, offering, venue) do
    Enum.reduce_while(occurrences, {:ok, []}, fn occurrence, {:ok, acc} ->
      session_attrs =
        attrs
        |> Map.put(:starts_at, occurrence.starts_at)
        |> Map.put(:ends_at, occurrence.ends_at)

      with {:ok, session} <- insert_session(session_attrs, offering, venue, series.id),
           {:ok, _coaches} <- put_coaches(session, coach_ids(attrs)),
           {:ok, session} <- reload_session(session) do
        {:cont, {:ok, [session | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sessions} -> {:ok, Enum.reverse(sessions)}
      other -> other
    end
  end

  defp put_coaches(_session, []), do: {:ok, []}

  defp put_coaches(session, coach_ids) do
    team_ids = team_membership_ids()

    case Enum.find(coach_ids, &(&1 not in team_ids)) do
      nil -> insert_coaches(session, coach_ids)
      invalid -> {:error, {:invalid_coach, invalid}}
    end
  end

  defp insert_coaches(session, coach_ids) do
    coach_ids
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {membership_id, index}, {:ok, acc} ->
      attrs = %{
        tenant_id: TenantContext.get_tenant_id(),
        session_id: session.id,
        membership_id: membership_id,
        lead: index == 0
      }

      case %SessionCoach{} |> SessionCoach.changeset(attrs) |> Repo.insert() do
        {:ok, coach} -> {:cont, {:ok, [coach | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, coaches} -> {:ok, Enum.reverse(coaches)}
      other -> other
    end
  end

  ## Private: updates

  defp do_update_session(session, attrs) do
    update_attrs =
      attrs
      |> take_attrs([
        :starts_at,
        :ends_at,
        :venue_id,
        :capacity,
        :visibility,
        :notes_public,
        :notes_staff,
        :title_override,
        :show_coaches,
        :access_mode,
        :party_size,
        :exclusive_household_id
      ])
      |> Map.new(fn
        {:starts_at, value} -> {:starts_at, parse_datetime(value)}
        {:ends_at, value} -> {:ends_at, parse_datetime(value)}
        other -> other
      end)

    with {:ok, updated} <- session |> Session.update_changeset(update_attrs) |> Repo.update(),
         {:ok, _} <- maybe_replace_coaches(updated, attrs) do
      {:ok, updated}
    end
  end

  defp maybe_replace_coaches(session, attrs) do
    case get_attr(attrs, :coach_ids) do
      nil ->
        {:ok, []}

      coach_ids ->
        Repo.delete_all(from sc in SessionCoach, where: sc.session_id == ^session.id)

        with {:ok, _coaches} <- put_coaches(session, coach_ids) do
          {:ok, []}
        end
    end
  end

  defp guard_single_update(%Session{} = session, attrs) do
    occupancy = Session.occupancy(session)

    case get_attr(attrs, :capacity) do
      new_capacity when is_integer(new_capacity) and new_capacity < occupancy ->
        {:error, {:capacity_below_bookings, occupancy}}

      _ ->
        :ok
    end
  end

  defp do_cancel_session(actor, session, reason) do
    with {:ok, updated} <-
           session |> Session.cancel_changeset(%{cancel_reason: reason}) |> Repo.update(),
         {:ok, _event} <-
           Events.publish("session.cancelled", %{
             session_id: session.id,
             tenant_id: session.tenant_id,
             reason: reason,
             booked_count: session.booked_count,
             held_count: session.held_count,
             starts_at: session.starts_at
           }),
         {:ok, _audit} <-
           Audit.record(actor, "scheduling.session.cancelled", updated, %{reason: reason}) do
      {:ok, %{session: updated, impact: impact(session)}}
    end
  end

  defp maybe_publish_rescheduled(before, after_session) do
    changed? =
      DateTime.compare(before.starts_at, after_session.starts_at) != :eq or
        DateTime.compare(before.ends_at, after_session.ends_at) != :eq or
        before.venue_id != after_session.venue_id

    if changed? and Session.occupancy(before) > 0 do
      Events.publish("session.rescheduled", %{
        session_id: after_session.id,
        tenant_id: after_session.tenant_id,
        previous_starts_at: before.starts_at,
        starts_at: after_session.starts_at,
        venue_id: after_session.venue_id
      })
    else
      {:ok, :unchanged}
    end
  end

  defp impact(session) do
    %{booked_count: session.booked_count, held_count: session.held_count}
  end

  ## Private: series edits

  defp series_targets(:single, session_id) do
    with {:ok, session} <- fetch_record(Session, session_id) do
      {:ok, session, [session]}
    end
  end

  defp series_targets(:following, session_id) do
    with {:ok, session} <- fetch_record(Session, session_id) do
      targets =
        if session.series_id do
          Repo.all(
            from(s in Session,
              where:
                s.series_id == ^session.series_id and s.starts_at >= ^session.starts_at and
                  s.status != :cancelled,
              order_by: [asc: s.starts_at]
            )
          )
        else
          [session]
        end

      {:ok, session, targets}
    end
  end

  defp series_targets(:all, series_id) do
    with {:ok, series} <- fetch_record(SessionSeries, series_id) do
      sessions =
        Repo.all(
          from(s in Session,
            where: s.series_id == ^series.id and s.status != :cancelled,
            order_by: [asc: s.starts_at],
            preload: [:series]
          )
        )

      {:ok, series, sessions}
    end
  end

  defp series_targets(_scope, _id), do: {:error, :invalid_scope}

  defp guard_series_update(targets, attrs, opts) do
    occupancy = targets |> Enum.map(&Session.occupancy/1) |> Enum.sum()
    new_capacity = get_attr(attrs, :capacity)

    cond do
      is_integer(new_capacity) and Enum.any?(targets, &(new_capacity < Session.occupancy(&1))) ->
        {:error, {:capacity_below_bookings, occupancy}}

      occupancy > 0 and structural_series_edit?(attrs) and
          not truthy?(Keyword.get(opts, :confirm)) ->
        {:error, {:bookings_exist, occupancy}}

      true ->
        :ok
    end
  end

  defp structural_series_edit?(attrs) do
    Enum.any?([:capacity, :start_time_local, :duration_minutes, :venue_id], fn key ->
      not is_nil(get_attr(attrs, key))
    end)
  end

  defp maybe_update_series(%SessionSeries{} = series, _scope, attrs) do
    update_attrs =
      attrs
      |> Map.take([:ends_on, :start_time_local, :duration_minutes, :timezone])
      |> Map.new(fn
        {:ends_on, value} -> {:ends_on, parse_date(value)}
        {:start_time_local, value} -> {:start_time_local, parse_time(value)}
        other -> other
      end)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    if update_attrs == %{} do
      {:ok, series}
    else
      series |> SessionSeries.changeset(update_attrs) |> Repo.update()
    end
  end

  defp maybe_update_series(_session, _scope, _attrs), do: {:ok, nil}

  defp apply_series_edit(targets, attrs) do
    Enum.reduce_while(targets, {:ok, []}, fn session, {:ok, acc} ->
      case edit_one(session, attrs) do
        {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sessions} -> {:ok, Enum.reverse(sessions)}
      other -> other
    end
  end

  defp edit_one(session, attrs) do
    session = Repo.preload(session, :series)

    base =
      take_attrs(attrs, [
        :capacity,
        :visibility,
        :title_override,
        :notes_public,
        :notes_staff,
        :venue_id,
        :show_coaches
      ])

    base =
      cond do
        get_attr(attrs, :start_time_local) ->
          timezone = get_attr(attrs, :timezone) || series_timezone(session)
          duration = get_attr(attrs, :duration_minutes) || series_duration(session)
          local_date = Recurrence.local_date(session.starts_at, timezone)

          case Recurrence.at(
                 timezone,
                 local_date,
                 parse_time(get_attr(attrs, :start_time_local)),
                 duration
               ) do
            {:ok, occurrence} ->
              base
              |> Map.put(:starts_at, occurrence.starts_at)
              |> Map.put(:ends_at, occurrence.ends_at)

            {:error, _reason} ->
              base
          end

        get_attr(attrs, :duration_minutes) ->
          Map.put(
            base,
            :ends_at,
            DateTime.add(session.starts_at, get_attr(attrs, :duration_minutes) * 60)
          )

        true ->
          base
      end

    with {:ok, updated} <- session |> Session.update_changeset(base) |> Repo.update(),
         {:ok, _} <- maybe_replace_coaches(updated, attrs) do
      {:ok, updated}
    end
  end

  defp series_timezone(%Session{series: %SessionSeries{timezone: timezone}}), do: timezone
  defp series_timezone(_session), do: "Etc/UTC"

  defp series_duration(%Session{series: %SessionSeries{duration_minutes: duration}}), do: duration
  defp series_duration(_session), do: 60

  ## Private: calendar

  defp do_calendar(filters, opts) do
    filters = normalize(filters)
    [from: from, to: to] = range(filters)

    query =
      Session
      |> where([s], s.starts_at >= ^from and s.starts_at <= ^to)
      |> filter_sessions(filters)
      |> order_by([s], asc: s.starts_at)

    query = query |> portal_calendar_query(opts) |> visible_calendar_query(opts)

    sessions = query |> Repo.all() |> Repo.preload(:session_coaches)
    build_entries(sessions, opts)
  end

  defp portal_calendar_query(query, opts) do
    if Keyword.get(opts, :portal),
      do: portal_household_query(query, Keyword.get(opts, :household_id)),
      else: query
  end

  defp portal_household_query(query, household_id) when is_binary(household_id) do
    where(
      query,
      [s],
      s.status == :scheduled and s.visibility == :public and
        (s.access_mode == :public or s.exclusive_household_id == ^household_id)
    )
  end

  defp portal_household_query(query, _household_id) do
    where(
      query,
      [s],
      s.status == :scheduled and s.visibility == :public and s.access_mode == :public
    )
  end

  defp visible_calendar_query(query, opts) do
    if Keyword.get(opts, :include_hidden) == true or Keyword.get(opts, :portal) == true,
      do: query,
      else: where(query, [s], s.visibility == :public)
  end

  defp build_entries(sessions, opts) do
    offerings = Map.new(Catalog.list_offerings(), &{&1.id, &1})
    venues = Map.new(Catalog.list_venues(), &{&1.id, &1})
    team = Map.new(Staff.list_team(), &{&1.id, &1})
    player = Keyword.get(opts, :player)

    warnings_by_session =
      sessions
      |> detect_for_sessions()
      |> Enum.group_by(& &1.session_id)

    sessions
    |> Enum.filter(fn session -> eligible_for_player?(session, player, offerings) end)
    |> Enum.map(fn session ->
      offering = Map.get(offerings, session.offering_id)
      venue = Map.get(venues, session.venue_id)

      coaches =
        if Keyword.get(opts, :portal, false) and session.show_coaches == false do
          []
        else
          Enum.map(session.session_coaches, &Map.get(team, &1.membership_id))
          |> Enum.reject(&is_nil/1)
        end

      %{
        session: session,
        offering: offering,
        venue: venue,
        coaches: coaches,
        seats_left: Session.seats_left(session),
        bookable: bookable?(session, offering),
        not_bookable_reason: not_bookable_reason(session, offering),
        already_booked: already_booked?(player, session),
        warnings: Map.get(warnings_by_session, session.id, [])
      }
    end)
  end

  defp portal_session_visible?(%Session{access_mode: :public}, _opts), do: true

  defp portal_session_visible?(
         %Session{access_mode: :private, exclusive_household_id: owner},
         opts
       ),
       do: is_binary(owner) and owner == Keyword.get(opts, :household_id)

  defp already_booked?(%{id: player_id}, %Session{id: session_id}),
    do: Bookings.player_booked_in_session?(player_id, session_id)

  defp already_booked?(_player, _session), do: false

  defp roster_for(session_id), do: Bookings.session_roster(session_id)

  defp eligible_for_player?(_session, nil, _offerings), do: true

  defp eligible_for_player?(session, player, offerings) do
    case Map.get(offerings, session.offering_id) do
      nil ->
        false

      offering ->
        age = SportsCoachBookings.Players.age_on(player, DateTime.to_date(session.starts_at))

        (is_nil(offering.min_age) or offering.min_age <= age) and
          (is_nil(offering.max_age) or offering.max_age >= age)
    end
  end

  defp bookable?(session, offering) do
    session.status == :scheduled and session.visibility == :public and
      not_bookable_reason(session, offering) == nil
  end

  defp not_bookable_reason(%Session{status: :cancelled}, _offering), do: :cancelled
  defp not_bookable_reason(%Session{status: :completed}, _offering), do: :too_late

  defp not_bookable_reason(%Session{} = session, offering) do
    cond do
      too_late?(session, offering) -> :too_late
      too_early?(session, offering) -> :too_early
      understaffed?(session, offering) -> :understaffed
      Session.seats_left(session) <= 0 -> :full
      true -> nil
    end
  end

  defp understaffed?(_session, nil), do: false

  defp understaffed?(session, offering) do
    {ratio, configured?} =
      if session.access_mode == :private do
        {offering.private_players_per_coach, map_size(offering.private_price_tiers || %{}) > 0}
      else
        {offering.public_players_per_coach, map_size(offering.public_price_tiers || %{}) > 0}
      end

    coach_count = length(session.session_coaches)

    configured? and coach_count > 0 and
      session.booked_count + session.held_count >= coach_count * (ratio || 1)
  end

  defp too_late?(session, offering) do
    minutes = (offering && offering.bookable_until_minutes_before) || 0
    threshold = DateTime.add(session.starts_at, -minutes * 60)
    DateTime.compare(DateTime.utc_now(), threshold) == :gt
  end

  defp too_early?(session, offering) do
    case offering && offering.bookable_from_days_ahead do
      nil ->
        false

      days ->
        horizon = DateTime.add(DateTime.utc_now(), days * 86_400)
        DateTime.compare(session.starts_at, horizon) == :gt
    end
  end

  ## Private: conflict detection

  @doc """
  Returns warnings for double-booked coaches and overlapping venue use across
  `sessions` and any other non-cancelled session in the loaded window.
  """
  @spec detect_for_sessions([Session.t()]) :: [map()]
  def detect_for_sessions([]), do: []

  def detect_for_sessions(sessions) do
    sessions = Repo.preload(sessions, :session_coaches)
    min = Enum.min(Enum.map(sessions, & &1.starts_at), DateTime)
    max = Enum.max(Enum.map(sessions, & &1.ends_at), DateTime)

    existing =
      Repo.all(
        from(s in Session,
          where: s.status != :cancelled and s.starts_at < ^max and s.ends_at > ^min,
          preload: [:session_coaches]
        )
      )

    by_id = Map.new(existing, &{&1.id, &1})

    for candidate <- sessions,
        conflicting <- existing,
        candidate.id != conflicting.id,
        overlap?(candidate, conflicting) do
      conflicts_for_pair(candidate, conflicting, by_id)
    end
    |> List.flatten()
  end

  defp overlap?(a, b) do
    DateTime.compare(a.starts_at, b.ends_at) == :lt and
      DateTime.compare(a.ends_at, b.starts_at) == :gt
  end

  defp conflicts_for_pair(candidate, conflicting, by_id) do
    venue_warning =
      if candidate.venue_id == conflicting.venue_id do
        [
          %{
            type: :venue_overlap,
            session_id: candidate.id,
            conflicting_session_id: conflicting.id,
            starts_at: candidate.starts_at
          }
        ]
      else
        []
      end

    candidate_coaches = coach_ids_of(Map.get(by_id, candidate.id, candidate))
    conflicting_coaches = coach_ids_of(conflicting)
    shared = candidate_coaches -- (candidate_coaches -- conflicting_coaches)

    coach_warnings =
      Enum.map(shared, fn membership_id ->
        %{
          type: :coach_double_booked,
          session_id: candidate.id,
          conflicting_session_id: conflicting.id,
          membership_id: membership_id,
          starts_at: candidate.starts_at
        }
      end)

    venue_warning ++ coach_warnings
  end

  defp coach_ids_of(%Session{session_coaches: coaches}), do: Enum.map(coaches, & &1.membership_id)
  defp coach_ids_of(_), do: []

  ## Private: filters, ranges, coercion

  defp filter_sessions(query, filters) do
    query
    |> where_value(:venue_id, filters)
    |> where_value(:offering_id, filters)
    |> where_value(:status, filters)
    |> where_value(:visibility, filters)
    |> filter_coach(Map.get(filters, "coach_id") || Map.get(filters, :coach_id))
  end

  defp where_value(query, field, filters) do
    value = Map.get(filters, to_string(field)) || Map.get(filters, field)

    case {field, value} do
      {_, nil} -> query
      {:venue_id, v} -> where(query, [s], s.venue_id == ^v)
      {:offering_id, v} -> where(query, [s], s.offering_id == ^v)
      {:status, v} -> where(query, [s], s.status == ^v)
      {:visibility, v} -> where(query, [s], s.visibility == ^v)
    end
  end

  defp filter_coach(query, nil), do: query

  defp filter_coach(query, membership_id) do
    join(query, :inner, [s], sc in SessionCoach,
      on: sc.session_id == s.id and sc.membership_id == ^membership_id
    )
  end

  defp range(filters) do
    filters = normalize(filters)
    now = DateTime.utc_now()
    from = parse_datetime(get_attr(filters, :from)) || now

    to =
      parse_datetime(get_attr(filters, :to)) || DateTime.add(from, @default_range_days * 86_400)

    [from: from, to: to]
  end

  defp portal_range(filters) do
    filters = normalize(filters)
    [from: from, to: to] = range(filters)

    if DateTime.diff(to, from, :second) > @max_portal_range_days * 86_400 do
      {:error, :range_too_large}
    else
      {from, to}
    end
  end

  defp coach_ids(attrs) do
    case get_attr(attrs, :coach_ids) do
      ids when is_list(ids) -> Enum.reject(ids, &is_nil/1)
      _ -> []
    end
  end

  defp team_membership_ids do
    Staff.list_team() |> Enum.map(& &1.id)
  end

  defp reload_session(session) do
    {:ok, Repo.preload(session, :session_coaches, force: true)}
  end

  defp fetch_record(schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp normalize(attrs), do: Enum.into(attrs, %{})

  defp get_attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  # HTTP request bodies have string keys; internal callers often use atoms.
  # `Map.take/2` only matches one form, so we read whichever key is present
  # (and preserve explicit `nil`/`false` values, unlike `get_attr/2`).
  defp take_attrs(attrs, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      string_key = to_string(field)

      cond do
        Map.has_key?(attrs, field) -> Map.put(acc, field, Map.get(attrs, field))
        Map.has_key?(attrs, string_key) -> Map.put(acc, field, Map.get(attrs, string_key))
        true -> acc
      end
    end)
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp parse_datetime(%DateTime{} = value), do: value
  defp parse_datetime(nil), do: nil

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

  defp unwrap_time({:ok, time}), do: time
  defp unwrap_time(_), do: nil

  defp parse_time(%Time{} = value), do: value
  defp parse_time(nil), do: nil

  defp parse_time(value) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} ->
        time

      {:error, _} ->
        case String.split(value, ":") do
          [h, m] ->
            Time.new(String.to_integer(h), String.to_integer(m), 0) |> unwrap_time()

          [h, m, s] ->
            Time.new(String.to_integer(h), String.to_integer(m), String.to_integer(s))
            |> unwrap_time()

          _ ->
            nil
        end
    end
  end

  defp parse_time(_), do: nil

  defp parse_date(%Date{} = value), do: value
  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(_), do: nil

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
