defmodule SportsCoachBookings.Bookings do
  @moduledoc """
  The booking engine. Owned by WP-14.

  Book, cancel, rebook, and record attendance for a player in a session,
  correctly under concurrency and with policy-driven outcomes. A booking stores
  the policy **snapshot** taken at booking time; cancellations and no-shows are
  evaluated against that snapshot by the pure `Policies.Engine`, never against
  the tenant's current policy.

  Every write runs inside `Repo.with_tenant_tx/2` (RLS) and moves the session
  counters only through `Scheduling.Seats`. Events (`booking.created`,
  `booking.cancelled`, `booking.rebooked`, `booking.attended`, `booking.no_show`)
  are published in the same transaction as the state change.
  """

  import Ecto.Query

  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Bookings.BookingEvent
  alias SportsCoachBookings.Bookings.ExpiredHoldWorker
  alias SportsCoachBookings.Bookings.Policy
  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Policies
  alias SportsCoachBookings.Policies.Engine
  alias SportsCoachBookings.Policies.Outcome
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookings.Scheduling.Seats
  alias SportsCoachBookings.Scheduling.Session
  alias SportsCoachBookings.Waivers

  @hold_minutes 30
  @attendance_window_days 7
  @free_change_days 7
  @active_statuses [:held, :confirmed, :attended]
  @roster_statuses [:held, :confirmed, :attended, :no_show]

  ## Reads

  @doc "Fetches a booking by id, raising if it does not exist for this tenant."
  @spec get_booking!(binary()) :: Booking.t()
  def get_booking!(id), do: read(fn -> Repo.get!(Booking, id) end)

  @doc "Fetches a booking by id, or `{:error, :not_found}`."
  @spec fetch_booking(binary()) :: {:ok, Booking.t()} | {:error, :not_found}
  def fetch_booking(id), do: read(fn -> fetch_record(Booking, id) end)

  @doc """
  Lists a household's bookings with their session and offering, newest first.

  Options: `:scope` — `:upcoming` (session still ahead and active), `:past`
  (session finished or terminal booking), or `:all` (default).
  """
  @spec list_for_household(binary(), keyword() | map()) :: [map()]
  def list_for_household(household_id, opts \\ []) do
    opts = Enum.into(opts, %{})

    read(fn ->
      household_id
      |> household_query()
      |> Repo.all()
      |> enrich()
      |> filter_scope(fetch(opts, :scope))
    end)
  end

  @doc "Paginates a household's bookings. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_for_household(binary(), map() | keyword(), keyword() | map()) ::
          %{data: [map()], next_cursor: binary() | nil}
  def page_for_household(household_id, params \\ %{}, opts \\ []) do
    opts = Enum.into(opts, %{})

    read(fn ->
      {rows, cursor} = Pagination.paginate(household_query(household_id), params)
      %{data: rows |> enrich() |> filter_scope(fetch(opts, :scope)), next_cursor: cursor}
    end)
  end

  @doc """
  Paginates bookings for staff history.

  Filters: `:status`, `:household_id`, `:player_id`, `:session_id`.
  """
  @spec page_bookings(map() | keyword(), map() | keyword()) ::
          %{data: [map()], next_cursor: binary() | nil}
  def page_bookings(filters \\ %{}, params \\ %{}) do
    read(fn ->
      query = Booking |> filter_bookings(Enum.into(filters, %{}))
      {rows, cursor} = Pagination.paginate(query, params)
      %{data: enrich(rows), next_cursor: cursor}
    end)
  end

  @doc "Lists a booking's history events, oldest first."
  @spec list_booking_events(binary()) :: [BookingEvent.t()]
  def list_booking_events(booking_id) do
    read(fn ->
      Repo.all(
        from e in BookingEvent,
          where: e.booking_id == ^booking_id,
          order_by: [asc: e.inserted_at]
      )
    end)
  end

  @doc """
  The roster rows for a session: booking, player summary, and payment info.

  Used by `SportsCoachBookings.Scheduling.Bookings` (the scheduling seam).
  """
  @spec session_roster(binary()) :: [map()]
  def session_roster(session_id) do
    read(fn ->
      bookings =
        Repo.all(
          from b in Booking,
            where: b.session_id == ^session_id and b.status in ^@roster_statuses,
            order_by: [asc: b.inserted_at]
        )

      summaries =
        bookings
        |> Enum.map(& &1.player_id)
        |> Players.summary_for_roster()
        |> Map.new(&{&1.id, &1})

      Enum.map(bookings, fn booking ->
        roster_row(booking, Map.get(summaries, booking.player_id))
      end)
    end)
  end

  @doc "Whether `player_id` already has a non-cancelled booking in `session_id`."
  @spec player_booked_in_session?(binary(), binary()) :: boolean()
  def player_booked_in_session?(player_id, session_id) do
    read(fn ->
      Repo.exists?(
        from b in Booking,
          where:
            b.player_id == ^player_id and b.session_id == ^session_id and
              b.status in ^@active_statuses
      )
    end)
  end

  ## Book

  @doc """
  Books `player_id` into `session_id`.

  `method_or_opts` is a payment method atom (`:credits`, `:paid`, `:comp`) or a
  keyword/map of options: `:method`/`:payment_method`, `:override`, `:reason`.

  Returns `{:ok, %Booking{}}` (a `held` booking for `:paid`) or an error tuple.
  """
  @spec book(Policy.actor(), binary(), binary(), atom() | keyword() | map()) ::
          {:ok, Booking.t()} | {:error, term()}
  def book(actor, player_id, session_id, method_or_opts \\ [])

  def book(actor, player_id, session_id, method) when is_atom(method),
    do: book(actor, player_id, session_id, method: method)

  def book(actor, player_id, session_id, opts)
      when is_binary(player_id) and is_binary(session_id) do
    opts = Enum.into(opts, %{})
    method = normalize_method(fetch(opts, :method) || fetch(opts, :payment_method))
    override = fetch(opts, :override) == true
    reason = fetch(opts, :reason)

    write(fn -> do_book(actor, player_id, session_id, method, override, reason, opts) end)
  end

  ## Cancel

  @doc """
  Cancels a booking, applying the policy outcome stored in its snapshot.

  Options: `:reason`, and (staff owner/admin only) `:outcome` — `:full_return`,
  `:forfeit`, `:credit_return`, `:provider_cancelled`, or `:partial_refund` with
  `:refund_pct`. Staff overrides are audited.
  """
  @spec cancel(Policy.actor(), binary(), keyword() | map()) ::
          {:ok, Booking.t()} | {:error, term()}
  def cancel(actor, booking_id, opts \\ []) do
    write(fn -> do_cancel(actor, booking_id, Enum.into(opts, %{})) end)
  end

  @doc "Returns the cancellation outcome for a booking without applying it."
  @spec cancel_preview(Policy.actor(), binary()) :: {:ok, map()} | {:error, term()}
  def cancel_preview(actor, booking_id) do
    read(fn -> do_cancel_preview(actor, booking_id) end)
  end

  ## Rebook

  @doc "Lists the sessions a booking may be rebooked into."
  @spec rebook_options(Policy.actor(), binary()) :: {:ok, map()} | {:error, term()}
  def rebook_options(actor, booking_id) do
    read(fn -> do_rebook_options(actor, booking_id) end)
  end

  @doc """
  Atomically rebooks a confirmed booking into `target_session_id`, carrying the
  same payment (credits or the paid order line) with no forfeit.
  """
  @spec rebook(Policy.actor(), binary(), binary(), keyword() | map()) ::
          {:ok, Booking.t()} | {:error, term()}
  def rebook(actor, booking_id, target_session_id, opts \\ []) do
    write(fn -> do_rebook(actor, booking_id, target_session_id, Enum.into(opts, %{})) end)
  end

  ## Attendance

  @doc """
  Marks a confirmed booking `:attended` or `:no_show`.

  Allowed from the session start until 7 days after, for an owner/admin or the
  session's coach.
  """
  @spec mark_attendance(Policy.actor(), binary(), atom()) ::
          {:ok, Booking.t()} | {:error, term()}
  def mark_attendance(actor, booking_id, status) when status in [:attended, :no_show] do
    write(fn -> do_mark_attendance(actor, booking_id, status) end)
  end

  def mark_attendance(_actor, _booking_id, _status) do
    {:error, {:invalid_attendance_status, "status must be attended or no_show"}}
  end

  ## Order / session subscribers

  @doc "Confirms the held bookings on a paid order. Idempotent."
  @spec confirm_order_holds(binary()) :: :ok | {:error, term()}
  def confirm_order_holds(order_id) when is_binary(order_id) do
    write(fn ->
      case Commerce.fetch_order(order_id) do
        {:ok, order} -> confirm_order_lines(order)
        {:error, _reason} -> :ok
      end
    end)
  end

  @doc "Releases the held bookings on an expired order. Idempotent."
  @spec release_order_holds(binary()) :: :ok | {:error, term()}
  def release_order_holds(order_id) when is_binary(order_id) do
    write(fn ->
      case Commerce.fetch_order(order_id) do
        {:ok, order} -> release_order_lines(order)
        {:error, _reason} -> :ok
      end
    end)
  end

  @doc """
  Cancels every active booking for a cancelled session with the
  `provider_cancelled` outcome (credits returned, paid bookings fully refunded).
  Idempotent.
  """
  @spec cancel_for_session(binary(), keyword() | map()) :: :ok | {:error, term()}
  def cancel_for_session(session_id, opts \\ []) do
    opts = Enum.into(opts, %{})

    write(fn ->
      bookings =
        Repo.all(
          from b in Booking,
            where: b.session_id == ^session_id and b.status in ^@active_statuses
        )

      Enum.each(bookings, fn booking ->
        cancel_one(
          booking.id,
          &provider_outcome/3,
          nil,
          fetch(opts, :reason) || "session cancelled"
        )
      end)

      :ok
    end)
  end

  @doc """
  Marks affected bookings as free to change (after a reschedule).

  `session.rescheduled` does not change bookings automatically; this sets
  `free_change_until` so the engine honours the free change window.
  """
  @spec set_free_change(binary(), DateTime.t() | nil) :: {:ok, non_neg_integer()}
  def set_free_change(session_id, until \\ nil) do
    until = until || DateTime.add(now(), @free_change_days, :day)

    write(fn ->
      {count, _} =
        Repo.update_all(
          from(b in Booking,
            where:
              b.session_id == ^session_id and b.status in ^@active_statuses and
                (is_nil(b.free_change_until) or b.free_change_until < ^until)
          ),
          set: [free_change_until: until, updated_at: now()]
        )

      {:ok, count}
    end)
  end

  @doc "Expires every held booking whose hold has lapsed. Idempotent."
  @spec expire_due_holds(DateTime.t() | nil) :: {:ok, non_neg_integer()}
  def expire_due_holds(now \\ nil) do
    now = now || now()

    write(fn ->
      ids =
        Repo.all(
          from b in Booking,
            where:
              b.status == :held and not is_nil(b.hold_expires_at) and
                b.hold_expires_at <= ^now,
            select: b.id,
            order_by: [asc: b.hold_expires_at, asc: b.id]
        )

      Enum.each(ids, &expire_one/1)
      {:ok, length(ids)}
    end)
  end

  @doc "Expires a single held booking if its hold has lapsed. Idempotent."
  @spec expire_hold(binary()) :: {:ok, :expired | :noop}
  def expire_hold(booking_id) when is_binary(booking_id) do
    write(fn -> do_expire_hold(booking_id) end)
  end

  defp do_expire_hold(booking_id) do
    case lock_booking(booking_id) do
      %Booking{status: :held, hold_expires_at: %DateTime{} = expires_at} = booking ->
        maybe_expire_hold(booking, expires_at)

      _ ->
        {:ok, :noop}
    end
  end

  defp maybe_expire_hold(booking, expires_at) do
    if DateTime.compare(expires_at, now()) != :gt do
      cancel_held(booking, "hold_expired")
      {:ok, :expired}
    else
      {:ok, :noop}
    end
  end

  ## Booking implementation

  defp do_book(actor, player_id, session_id, method, override, reason, _opts) do
    with :ok <- check_method(method, actor),
         {:ok, player} <- fetch_player(player_id),
         :ok <- authorize_household(actor, player),
         {:ok, session} <- lock_session(session_id),
         {:ok, offering} <- fetch_offering(session.offering_id),
         :ok <- check_session_status(session),
         :ok <- check_window(session, offering, actor, override, reason),
         :ok <- check_age(player, session, offering),
         :ok <- check_bookable(player),
         :ok <- check_waivers(player_id, offering.id),
         :ok <- check_duplicate(session_id, player_id),
         :ok <- check_overlap(player_id, session),
         :ok <- check_capacity(session) do
      insert_booking_for(actor, player, session, offering, method, reason)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp check_method(:credits, _actor), do: :ok
  defp check_method(:paid, _actor), do: :ok

  defp check_method(:comp, actor) do
    if staff_manager?(actor),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp check_method(_method, _actor),
    do: {:error, {:invalid_payment_method, "method must be credits, paid, or comp"}}

  defp authorize_household(%CustomerActor{household_id: household_id}, %Player{
         household_id: household_id
       }),
       do: :ok

  defp authorize_household(%StaffActor{role: role}, %Player{}) when role in [:owner, :admin],
    do: :ok

  defp authorize_household(_actor, _player), do: {:error, :forbidden}

  defp check_session_status(%Session{status: :scheduled}), do: :ok

  defp check_session_status(_session),
    do: {:error, {:session_not_bookable, "This session is not open for booking"}}

  defp check_window(session, offering, actor, override, reason) do
    reference = now()
    minutes = offering.bookable_until_minutes_before || 0
    too_late? = DateTime.compare(reference, DateTime.add(session.starts_at, -minutes * 60)) == :gt
    too_early? = too_early?(session, offering, reference)

    cond do
      not too_late? and not too_early? ->
        :ok

      override and staff_manager?(actor) ->
        _ =
          Audit.record(actor, "bookings.booking.window_override", nil, %{
            session_id: session.id,
            reason: reason
          })

        :ok

      too_late? ->
        {:error, {:too_late, "Booking for this session has closed"}}

      true ->
        {:error, {:too_early, "This session is not yet open for booking"}}
    end
  end

  defp too_early?(_session, %{bookable_from_days_ahead: nil}, _reference), do: false

  defp too_early?(session, offering, reference) do
    horizon = DateTime.add(reference, offering.bookable_from_days_ahead * 86_400)
    DateTime.compare(session.starts_at, horizon) == :gt
  end

  defp check_age(%Player{date_of_birth: nil}, _session, _offering), do: :ok

  defp check_age(%Player{} = player, session, offering) do
    age = Players.age_on(player, DateTime.to_date(session.starts_at))

    cond do
      offering.min_age && age < offering.min_age ->
        {:error,
         {:age_restricted, "Player is too young for this session",
          %{age: age, min_age: offering.min_age, max_age: offering.max_age}}}

      offering.max_age && age > offering.max_age ->
        {:error,
         {:age_restricted, "Player is too old for this session",
          %{age: age, min_age: offering.min_age, max_age: offering.max_age}}}

      true ->
        :ok
    end
  end

  defp check_bookable(player) do
    case Players.bookable?(player) do
      :ok ->
        :ok

      {:error, reasons} ->
        {:error,
         {:player_not_bookable, "The player cannot be booked",
          %{reasons: Enum.map(reasons, &to_string/1)}}}
    end
  end

  defp check_waivers(player_id, offering_id) do
    case Waivers.missing_for(player_id, offering_id) do
      [] ->
        :ok

      missing ->
        {:error,
         {:waivers_required, "Sign the required waiver(s) before booking",
          %{waivers: Enum.map(missing, &serialize_waiver/1)}}}
    end
  end

  defp check_duplicate(session_id, player_id) do
    if Repo.exists?(
         from b in Booking,
           where:
             b.session_id == ^session_id and b.player_id == ^player_id and
               b.status in ^@active_statuses
       ) do
      {:error, {:already_booked, "The player already has a booking for this session"}}
    else
      :ok
    end
  end

  defp check_overlap(player_id, session, except_booking_id \\ nil) do
    conflict? =
      Booking
      |> where(
        [b],
        b.player_id == ^player_id and b.status in ^@active_statuses and
          b.session_id != ^session.id
      )
      |> maybe_except(except_booking_id)
      |> Repo.all()
      |> Enum.any?(fn booking ->
        case safe_session(booking.session_id) do
          nil -> false
          other -> other.status == :scheduled and overlap?(session, other)
        end
      end)

    if conflict?,
      do: {:error, {:player_conflict, "The player is booked in an overlapping session"}},
      else: :ok
  end

  defp maybe_except(query, nil), do: query
  defp maybe_except(query, booking_id), do: where(query, [b], b.id != ^booking_id)

  defp overlap?(a, b) do
    DateTime.compare(a.starts_at, b.ends_at) == :lt and
      DateTime.compare(a.ends_at, b.starts_at) == :gt
  end

  defp check_capacity(session) do
    if session.booked_count + session.held_count < session.capacity,
      do: :ok,
      else: {:error, :session_full}
  end

  defp insert_booking_for(actor, player, session, offering, :paid, _reason) do
    hold_expires_at = DateTime.add(now(), @hold_minutes, :minute)
    base = base_attrs(actor, player, session, :paid)

    attrs =
      Map.merge(base, %{
        status: :held,
        credits_used: 0,
        hold_expires_at: hold_expires_at,
        paid_amount: offering.drop_in_price || 0
      })

    with {:ok, booking} <- insert_booking(attrs),
         {:ok, _session} <- adjust_session(session, 0, 1),
         {:ok, _event} <- insert_event(booking, "held", actor, %{method: "paid"}),
         {:ok, _job} <- schedule_hold_expiry(booking) do
      {:ok, booking}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp insert_booking_for(actor, player, session, offering, :comp, reason) do
    attrs =
      base_attrs(actor, player, session, :comp)
      |> Map.merge(%{status: :confirmed, credits_used: 0})

    with {:ok, booking} <- insert_booking(attrs),
         {:ok, _session} <- adjust_session(session, 1, 0),
         {:ok, _audit} <-
           Audit.record(actor, "bookings.booking.comped", booking, %{
             offering_id: offering.id,
             reason: reason
           }),
         {:ok, _event} <- insert_event(booking, "confirmed", actor, %{method: "comp"}),
         {:ok, _job} <- publish_created(booking) do
      {:ok, booking}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp insert_booking_for(actor, player, session, offering, :credits, _reason) do
    cost = offering.credit_cost || 0

    attrs =
      base_attrs(actor, player, session, :credits)
      |> Map.merge(%{status: :confirmed, credits_used: cost})

    with {:ok, booking} <- insert_booking(attrs),
         :ok <- consume_credits(booking, offering.id, cost, actor),
         {:ok, _session} <- adjust_session(session, 1, 0),
         {:ok, _event} <-
           insert_event(booking, "confirmed", actor, %{method: "credits", credits_used: cost}),
         {:ok, _job} <- publish_created(booking) do
      {:ok, booking}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp base_attrs(actor, player, session, method) do
    {actor_type, actor_id} = actor_fields(actor)

    %{
      tenant_id: TenantContext.get_tenant_id(),
      session_id: session.id,
      player_id: player.id,
      household_id: player.household_id,
      booked_by_type: actor_type,
      booked_by_id: actor_id,
      payment_method: method,
      policy_snapshot: Policies.snapshot_for(session.offering_id),
      currency: tenant_currency()
    }
  end

  defp insert_booking(attrs) do
    %Booking{} |> Booking.create_changeset(attrs) |> Repo.insert()
  end

  defp consume_credits(_booking, _offering_id, 0, _actor), do: :ok

  defp consume_credits(booking, offering_id, cost, actor) do
    case Credits.consume(booking.household_id, offering_id, cost,
           booking_id: booking.id,
           actor: actor,
           note: "booking"
         ) do
      {:ok, _entries} -> :ok
      {:error, :insufficient_credits} -> {:error, {:insufficient_credits, "Not enough credits"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp adjust_session(session, booked_delta, held_delta) do
    case Seats.adjust!(session, booked_delta, held_delta) do
      {:ok, updated} -> {:ok, updated}
      {:error, :capacity_exceeded} -> {:error, :session_full}
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish_created(booking) do
    Events.publish("booking.created", %{
      booking_id: booking.id,
      tenant_id: booking.tenant_id,
      session_id: booking.session_id,
      player_id: booking.player_id,
      household_id: booking.household_id,
      status: to_string(booking.status)
    })
  end

  defp schedule_hold_expiry(%Booking{hold_expires_at: nil}), do: {:ok, :none}

  defp schedule_hold_expiry(booking) do
    %{"tenant_id" => booking.tenant_id, "booking_id" => booking.id}
    |> ExpiredHoldWorker.new(scheduled_at: booking.hold_expires_at)
    |> Oban.insert()
  end

  ## Cancel implementation

  defp do_cancel(actor, booking_id, opts) do
    case lock_booking(booking_id) do
      nil ->
        Repo.rollback(:not_found)

      %Booking{status: :cancelled} = booking ->
        {:ok, booking}

      %Booking{} = booking ->
        if fetch(opts, :outcome) && not staff_manager?(actor) do
          Repo.rollback(:forbidden)
        end

        with :ok <- authorize_cancel(actor, booking),
             {:ok, session} <- fetch_session_required(booking.session_id),
             {:ok, offering} <- fetch_offering_required(session.offering_id) do
          outcome = resolve_cancel_outcome(actor, booking, session, offering, opts)
          apply_cancel(actor, booking, session, outcome, opts)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp authorize_cancel(%CustomerActor{household_id: household_id}, %Booking{
         household_id: household_id
       }),
       do: :ok

  defp authorize_cancel(%StaffActor{role: role}, %Booking{}) when role in [:owner, :admin],
    do: :ok

  defp authorize_cancel(_actor, _booking), do: {:error, :forbidden}

  defp resolve_cancel_outcome(actor, booking, session, offering, opts) do
    cond do
      match?(%Outcome{}, override = override_outcome(actor, booking, opts)) ->
        override

      free_change?(booking) ->
        # A reschedule granted this booking a free change window: return credits
        # and refund paid money in full regardless of the cancellation tier.
        %Outcome{allowed?: true, credit_outcome: :return, refund_amount: paid_money(booking)}

      true ->
        Engine.evaluate(booking.policy_snapshot, facts(booking, session, offering, :cancel))
    end
  end

  defp free_change?(%Booking{free_change_until: %DateTime{} = until}) do
    DateTime.compare(now(), until) != :gt
  end

  defp free_change?(_booking), do: false

  defp override_outcome(actor, booking, opts) do
    case fetch(opts, :outcome) do
      nil ->
        nil

      outcome when outcome in [:full_return, :forfeit, :credit_return, :provider_cancelled] ->
        if staff_manager?(actor), do: build_override(booking, outcome, opts), else: nil

      :partial_refund ->
        if staff_manager?(actor), do: build_override(booking, :partial_refund, opts), else: nil

      _other ->
        nil
    end
  end

  defp build_override(booking, :full_return, _opts) do
    %Outcome{allowed?: true, credit_outcome: :return, refund_amount: paid_money(booking)}
  end

  defp build_override(_booking, :forfeit, _opts) do
    %Outcome{allowed?: true, credit_outcome: :forfeit, refund_amount: nil}
  end

  defp build_override(_booking, :credit_return, _opts) do
    %Outcome{allowed?: true, credit_outcome: :return, refund_amount: nil}
  end

  defp build_override(booking, :provider_cancelled, _opts) do
    %Outcome{allowed?: true, credit_outcome: :return, refund_amount: paid_money(booking)}
  end

  defp build_override(booking, :partial_refund, opts) do
    pct = number(fetch(opts, :refund_pct)) || 0
    full = paid_money(booking)

    refund = if full, do: Money.percent(full, pct), else: nil
    %Outcome{allowed?: true, credit_outcome: :forfeit, refund_amount: refund}
  end

  defp apply_cancel(actor, booking, session, %Outcome{} = outcome, opts) do
    reason = fetch(opts, :reason) || "cancelled"

    with :ok <- reverse_credits(booking, outcome, actor, reason),
         :ok <- refund_paid(booking, outcome, actor, reason),
         :ok <- release_seat(booking, session),
         {:ok, updated} <- update_cancelled(booking, outcome, :cancel, reason),
         {:ok, _event} <-
           insert_event(updated, "cancelled", actor, %{
             outcome: outcome_map(outcome, :cancel),
             reason: reason
           }),
         {:ok, _job} <- publish_cancelled(updated, outcome),
         :ok <- audit_override(actor, booking, outcome, opts) do
      {:ok, updated}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reverse_credits(_booking, %Outcome{credit_outcome: outcome}, _actor, _reason)
       when outcome != :return,
       do: :ok

  defp reverse_credits(%Booking{credits_used: 0}, _outcome, _actor, _reason), do: :ok

  defp reverse_credits(booking, _outcome, actor, reason) do
    case Credits.reverse(booking.id, actor: actor, note: reason) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp refund_paid(
         %Booking{payment_method: :paid, order_line_id: order_line_id} = _booking,
         %Outcome{refund_amount: %Money{} = money},
         actor,
         reason
       )
       when is_binary(order_line_id) do
    if money.amount > 0 do
      case Commerce.refund_line(order_line_id, money, reason, actor) do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, {:refund_failed, to_string(reason)}}
      end
    else
      :ok
    end
  end

  defp refund_paid(_booking, _outcome, _actor, _reason), do: :ok

  defp release_seat(%Booking{status: :held}, session), do: adjust_ignore(session, 0, -1)

  defp release_seat(%Booking{status: status}, session)
       when status in [:confirmed, :attended, :no_show],
       do: adjust_ignore(session, -1, 0)

  defp release_seat(_booking, _session), do: :ok

  defp adjust_ignore(session, booked_delta, held_delta) do
    case Seats.adjust!(session, booked_delta, held_delta) do
      {:ok, _updated} -> :ok
      {:error, :negative_count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_cancelled(booking, outcome, action, reason) do
    booking
    |> Booking.update_changeset(%{
      status: :cancelled,
      cancelled_at: now(),
      cancel_outcome: outcome_map(outcome, action) |> Map.put("reason", reason)
    })
    |> Repo.update()
  end

  defp publish_cancelled(booking, outcome) do
    Events.publish("booking.cancelled", %{
      booking_id: booking.id,
      tenant_id: booking.tenant_id,
      session_id: booking.session_id,
      player_id: booking.player_id,
      household_id: booking.household_id,
      credit_outcome: outcome.credit_outcome && to_string(outcome.credit_outcome),
      refund_amount: refund_amount(outcome.refund_amount)
    })
  end

  defp audit_override(actor, booking, outcome, opts) do
    if fetch(opts, :outcome) do
      _ =
        Audit.record(actor, "bookings.booking.cancelled_override", booking, %{
          reason: fetch(opts, :reason),
          outcome: outcome_map(outcome, :cancel)
        })
    end

    :ok
  end

  defp do_cancel_preview(actor, booking_id) do
    case Repo.get(Booking, booking_id) do
      nil ->
        {:error, :not_found}

      %Booking{status: :cancelled} = booking ->
        {:ok, %{booking: booking, already_cancelled: true, outcome: booking.cancel_outcome}}

      %Booking{} = booking ->
        with :ok <- authorize_cancel(actor, booking),
             {:ok, session} <- fetch_session_required(booking.session_id),
             {:ok, offering} <- fetch_offering_required(session.offering_id) do
          outcome = resolve_cancel_outcome(actor, booking, session, offering, %{})

          {:ok,
           %{booking: booking, already_cancelled: false, outcome: outcome_map(outcome, :cancel)}}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  ## Rebook implementation

  defp do_rebook(actor, booking_id, target_session_id, opts) do
    case lock_booking(booking_id) do
      nil ->
        Repo.rollback(:not_found)

      %Booking{status: status} when status not in [:confirmed, :attended] ->
        Repo.rollback({:not_rebookable, "Only a confirmed booking can be rebooked"})

      %Booking{} = booking ->
        do_rebook_locked(actor, booking, target_session_id, opts)
    end
  end

  defp do_rebook_locked(actor, booking, target_session_id, opts) do
    if target_session_id == booking.session_id do
      Repo.rollback({:not_rebookable, "The target session is the current session"})
    end

    with :ok <- authorize_cancel(actor, booking),
         {:ok, sessions} <- lock_sessions([booking.session_id, target_session_id]),
         {:ok, source_session} <- Map.fetch(sessions, booking.session_id),
         {:ok, target_session} <- Map.fetch(sessions, target_session_id),
         {:ok, source_offering} <- fetch_offering_required(source_session.offering_id),
         {:ok, target_offering} <- fetch_offering_required(target_session.offering_id),
         :ok <- check_rebook_policy(booking, source_session, source_offering, target_offering),
         :ok <- check_target(booking, target_session, target_offering) do
      create_rebook(actor, booking, source_session, target_session, target_offering, opts)
    else
      {:error, reason} -> Repo.rollback(reason)
      :error -> Repo.rollback(:not_found)
    end
  end

  defp check_rebook_policy(booking, source_session, source_offering, target_offering) do
    facts =
      facts(booking, source_session, source_offering, :rebook, %{
        target_offering_id: target_offering.id
      })

    case Engine.evaluate(booking.policy_snapshot, facts) do
      %Outcome{allowed?: true} -> :ok
      %Outcome{reason: reason} -> {:error, {:rebook_not_allowed, reason_message(reason)}}
    end
  end

  defp check_target(booking, target_session, target_offering) do
    with :ok <- check_session_status(target_session),
         :ok <- check_window(target_session, target_offering, nil, false, nil),
         {:ok, player} <- fetch_player(booking.player_id),
         :ok <- check_age(player, target_session, target_offering),
         :ok <- check_bookable(player),
         :ok <- check_waivers(booking.player_id, target_offering.id),
         :ok <- check_duplicate(target_session.id, booking.player_id),
         :ok <- check_overlap(player.id, target_session, booking.id),
         :ok <- check_capacity(target_session) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_rebook(actor, booking, source_session, target_session, target_offering, opts) do
    {actor_type, actor_id} = actor_fields(actor)

    attrs = %{
      tenant_id: booking.tenant_id,
      session_id: target_session.id,
      player_id: booking.player_id,
      household_id: booking.household_id,
      booked_by_type: actor_type,
      booked_by_id: actor_id,
      status: :confirmed,
      payment_method: booking.payment_method,
      credits_used: booking.credits_used,
      order_line_id: booking.order_line_id,
      paid_amount: booking.paid_amount,
      currency: booking.currency,
      policy_snapshot: Policies.snapshot_for(target_offering.id),
      rebook_count: booking.rebook_count + 1,
      rebooked_from_id: booking.id
    }

    with {:ok, new_booking} <- insert_booking(attrs),
         :ok <- move_credits(booking, new_booking, target_offering.id, actor),
         :ok <- release_seat(booking, source_session),
         {:ok, _session} <- adjust_session(target_session, 1, 0),
         {:ok, _old} <- mark_rebooked(booking, new_booking, opts),
         {:ok, _events} <- rebook_events(actor, booking, new_booking),
         {:ok, _job} <- publish_rebooked(booking, new_booking) do
      {:ok, new_booking}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp move_credits(%Booking{credits_used: 0}, _new, _offering_id, _actor), do: :ok

  defp move_credits(old, new, offering_id, actor) do
    with {:ok, _reversed} <- Credits.reverse(old.id, actor: actor, note: "rebook"),
         {:ok, _entries} <-
           Credits.consume(new.household_id, offering_id, old.credits_used,
             booking_id: new.id,
             actor: actor,
             note: "rebook"
           ) do
      :ok
    else
      {:error, :insufficient_credits} ->
        {:error, {:insufficient_credits, "The target offering has no eligible credits"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_rebooked(booking, new_booking, _opts) do
    booking
    |> Booking.update_changeset(%{
      status: :cancelled,
      cancelled_at: now(),
      rebooked_to_id: new_booking.id,
      cancel_outcome: %{
        "action" => "rebook",
        "credit_outcome" => nil,
        "refund_amount" => 0,
        "moved_to" => new_booking.id
      }
    })
    |> Repo.update()
  end

  defp rebook_events(actor, old, new) do
    with {:ok, _} <-
           insert_event(old, "rebooked", actor, %{rebooked_to_id: new.id}),
         {:ok, _} <-
           insert_event(new, "rebooked", actor, %{rebooked_from_id: old.id}) do
      {:ok, :ok}
    end
  end

  defp publish_rebooked(old, new) do
    Events.publish("booking.rebooked", %{
      booking_id: new.id,
      from_booking_id: old.id,
      tenant_id: new.tenant_id,
      session_id: new.session_id,
      source_session_id: old.session_id,
      player_id: new.player_id,
      household_id: new.household_id
    })
  end

  defp do_rebook_options(actor, booking_id) do
    case Repo.get(Booking, booking_id) do
      nil ->
        {:error, :not_found}

      %Booking{} = booking ->
        with :ok <- authorize_cancel(actor, booking),
             {:ok, session} <- fetch_session_required(booking.session_id),
             {:ok, offering} <- fetch_offering_required(session.offering_id) do
          build_rebook_options(actor, booking, session, offering)
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp build_rebook_options(_actor, booking, session, offering) do
    facts = facts(booking, session, offering, :rebook, %{target_offering_id: offering.id})
    outcome = Engine.evaluate(booking.policy_snapshot, facts)

    if outcome.allowed? do
      now = now()
      horizon = DateTime.add(now, 90, :day)

      candidates =
        Scheduling.list_sessions(%{offering_id: offering.id, from: now, to: horizon})
        |> Enum.filter(fn candidate ->
          candidate.id != session.id and candidate.status == :scheduled and
            candidate.booked_count + candidate.held_count < candidate.capacity and
            DateTime.compare(candidate.starts_at, now) != :lt
        end)

      offerings = Map.new(Catalog.list_offerings(), &{&1.id, &1})

      {:ok,
       %{
         allowed: true,
         reason: nil,
         sessions:
           Enum.map(candidates, fn candidate ->
             %{session: candidate, offering: Map.get(offerings, candidate.offering_id)}
           end)
       }}
    else
      {:ok, %{allowed: false, reason: reason_message(outcome.reason), sessions: []}}
    end
  end

  ## Attendance implementation

  defp do_mark_attendance(actor, booking_id, status) do
    case lock_booking(booking_id) do
      nil ->
        Repo.rollback(:not_found)

      %Booking{status: ^status} = booking ->
        {:ok, booking}

      %Booking{status: booking_status} = booking
      when booking_status in [:confirmed, :attended, :no_show] ->
        with :ok <- authorize_attendance(actor, booking),
             {:ok, session} <- fetch_session_required(booking.session_id),
             :ok <- check_attendance_window(session) do
          apply_attendance(actor, booking, session, status)
        else
          {:error, reason} -> Repo.rollback(reason)
        end

      %Booking{} ->
        Repo.rollback({:not_attendance_ready, "The booking is not confirmed"})
    end
  end

  defp authorize_attendance(%StaffActor{role: role}, _booking) when role in [:owner, :admin],
    do: :ok

  defp authorize_attendance(%StaffActor{role: :coach} = actor, booking) do
    if coach_assigned?(actor, booking.session_id), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_attendance(_actor, _booking), do: {:error, :forbidden}

  defp check_attendance_window(session) do
    reference = now()
    deadline = DateTime.add(session.starts_at, @attendance_window_days, :day)

    cond do
      DateTime.compare(reference, session.starts_at) == :lt ->
        {:error, {:too_early, "Attendance opens when the session starts"}}

      DateTime.compare(reference, deadline) == :gt ->
        {:error, {:too_late, "Attendance is closed"}}

      true ->
        :ok
    end
  end

  defp apply_attendance(actor, booking, _session, :attended) do
    with {:ok, updated} <-
           booking
           |> Booking.update_changeset(%{status: :attended})
           |> Repo.update(),
         {:ok, _event} <- insert_event(updated, "attended", actor, %{}),
         {:ok, _job} <-
           Events.publish("booking.attended", %{
             booking_id: updated.id,
             tenant_id: updated.tenant_id,
             session_id: updated.session_id,
             player_id: updated.player_id,
             household_id: updated.household_id
           }) do
      {:ok, updated}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp apply_attendance(actor, booking, session, :no_show) do
    offering = fetch_offering_required(session.offering_id) |> elem_or_nil()

    outcome =
      Engine.evaluate(booking.policy_snapshot, facts(booking, session, offering, :no_show))

    with :ok <- reverse_credits(booking, outcome, actor, "no_show"),
         :ok <- refund_paid(booking, outcome, actor, "no_show"),
         {:ok, updated} <-
           booking
           |> Booking.update_changeset(%{
             status: :no_show,
             cancel_outcome: outcome_map(outcome, :no_show)
           })
           |> Repo.update(),
         {:ok, _event} <-
           insert_event(updated, "no_show", actor, %{outcome: outcome_map(outcome, :no_show)}),
         {:ok, _job} <-
           Events.publish("booking.no_show", %{
             booking_id: updated.id,
             tenant_id: updated.tenant_id,
             session_id: updated.session_id,
             player_id: updated.player_id,
             household_id: updated.household_id,
             credit_outcome: outcome.credit_outcome && to_string(outcome.credit_outcome)
           }) do
      {:ok, updated}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp elem_or_nil({:ok, value}), do: value
  defp elem_or_nil(_), do: nil

  ## Order/session internals

  # Dialyxir: the fallback clauses below are defensive; unreachable per inferred
  # types (every caller passes an `%Order{}`).
  @dialyzer {:nowarn_function, confirm_order_lines: 1}
  defp confirm_order_lines(%{lines: lines}) do
    Enum.each(lines, fn line ->
      if is_binary(line.booking_id), do: confirm_hold(line.booking_id, line.id)
    end)

    :ok
  end

  defp confirm_order_lines(_order), do: :ok

  defp confirm_hold(booking_id, order_line_id) do
    case lock_booking(booking_id) do
      %Booking{status: :held} = booking ->
        with {:ok, updated} <-
               booking
               |> Booking.update_changeset(%{
                 status: :confirmed,
                 order_line_id: order_line_id,
                 hold_expires_at: nil
               })
               |> Repo.update(),
             {:ok, _session} <- Seats.confirm_hold(updated.session_id, 1),
             {:ok, _event} <-
               insert_event(updated, "confirmed", nil, %{order_line_id: order_line_id}),
             {:ok, _job} <- publish_created(updated) do
          :ok
        else
          {:error, reason} -> Repo.rollback(reason)
        end

      _ ->
        :ok
    end
  end

  @dialyzer {:nowarn_function, release_order_lines: 1}
  defp release_order_lines(%{lines: lines}) do
    Enum.each(lines, fn line ->
      if is_binary(line.booking_id), do: release_held!(line.booking_id)
    end)

    :ok
  end

  defp release_order_lines(_order), do: :ok

  defp cancel_one(booking_id, outcome_fun, actor, reason) do
    case lock_booking(booking_id) do
      nil ->
        :ok

      %Booking{status: :cancelled} ->
        :ok

      %Booking{} = booking ->
        cancel_locked(booking, outcome_fun, actor, reason)
    end
  end

  # `apply_cancel/5` rolls back on every error path, so it always returns
  # `{:ok, _}`; the error branch is kept defensively.
  @dialyzer {:nowarn_function, cancel_locked: 4}
  defp cancel_locked(booking, outcome_fun, actor, reason) do
    with {:ok, session} <- fetch_session_required(booking.session_id),
         {:ok, offering} <- fetch_offering_required(session.offering_id) do
      outcome = outcome_fun.(booking, session, offering)

      case apply_cancel(actor, booking, session, outcome, %{reason: reason}) do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp provider_outcome(booking, session, offering) do
    Engine.evaluate(booking.policy_snapshot, facts(booking, session, offering, :provider_cancel))
  end

  defp expire_one(booking_id) do
    case lock_booking(booking_id) do
      %Booking{status: :held} = booking -> cancel_held(booking, "hold_expired")
      _ -> :ok
    end
  end

  defp release_held!(booking_id) do
    case lock_booking(booking_id) do
      %Booking{status: :held} = booking -> cancel_held(booking, "order_expired")
      _ -> :ok
    end
  end

  defp cancel_held(booking, action) do
    now = now()

    with :ok <- release_seat(booking, lock_session!(booking.session_id)),
         {:ok, updated} <-
           booking
           |> Booking.update_changeset(%{
             status: :cancelled,
             cancelled_at: now,
             cancel_outcome: %{
               "action" => action,
               "credit_outcome" => nil,
               "refund_amount" => 0
             }
           })
           |> Repo.update(),
         {:ok, _event} <- insert_event(updated, action, nil, %{}) do
      :ok
    end
  end

  ## Shared helpers

  defp facts(booking, session, offering, action, extra \\ %{}) do
    Map.merge(
      %{
        action: action,
        session_starts_at: session.starts_at,
        now: now(),
        payment_method: booking.payment_method,
        amount_paid: paid_money(booking),
        rebook_count: booking.rebook_count,
        source_offering_id: offering && offering.id,
        target_offering_id: nil
      },
      extra
    )
  end

  defp paid_money(%Booking{payment_method: :paid} = booking),
    do: Money.new(booking.paid_amount || 0, booking.currency || tenant_currency())

  defp paid_money(_booking), do: nil

  defp outcome_map(%Outcome{} = outcome, action) do
    %{
      "action" => to_string(action),
      "allowed" => outcome.allowed?,
      "reason" => outcome.reason && to_string(outcome.reason),
      "credit_outcome" => outcome.credit_outcome && to_string(outcome.credit_outcome),
      "refund_amount" => refund_amount(outcome.refund_amount),
      "currency" => refund_currency(outcome.refund_amount),
      "tier_matched" => outcome.tier_matched
    }
  end

  defp refund_amount(%Money{amount: amount}), do: amount
  defp refund_amount(_money), do: 0

  defp refund_currency(%Money{currency: currency}), do: currency
  defp refund_currency(_money), do: nil

  defp reason_message(nil), do: "rebooking is not allowed"
  defp reason_message(reason), do: to_string(reason)

  defp serialize_waiver(waiver) do
    %{
      "template_id" => waiver.template_id,
      "version_id" => waiver.version_id,
      "name" => waiver.name
    }
  end

  defp insert_event(booking, kind, actor, data) do
    {actor_type, actor_id} = actor_fields(actor)

    %BookingEvent{}
    |> BookingEvent.changeset(%{
      tenant_id: booking.tenant_id,
      booking_id: booking.id,
      kind: kind,
      actor_type: actor_type,
      actor_id: actor_id,
      data: stringify_keys(data)
    })
    |> Repo.insert()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp stringify_value(%Money{} = value), do: Money.to_map(value)
  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)

  defp stringify_value(value) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: to_string(value)

  defp stringify_value(value), do: value

  defp roster_row(booking, summary) do
    %{
      booking_id: booking.id,
      player_id: booking.player_id,
      player_name: summary && summary.name,
      status: to_string(booking.status),
      payment_method: to_string(booking.payment_method),
      credits_used: booking.credits_used,
      hold_expires_at: booking.hold_expires_at
    }
  end

  defp household_query(household_id) do
    from b in Booking,
      where: b.household_id == ^household_id,
      order_by: [desc: b.inserted_at]
  end

  defp filter_bookings(query, filters) do
    query
    |> filter_status(fetch(filters, :status))
    |> filter_household(fetch(filters, :household_id))
    |> filter_player(fetch(filters, :player_id))
    |> filter_session(fetch(filters, :session_id))
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: where(query, [b], b.status == ^normalize_status(status))

  defp filter_household(query, nil), do: query
  defp filter_household(query, id), do: where(query, [b], b.household_id == ^id)

  defp filter_player(query, nil), do: query
  defp filter_player(query, id), do: where(query, [b], b.player_id == ^id)

  defp filter_session(query, nil), do: query
  defp filter_session(query, id), do: where(query, [b], b.session_id == ^id)

  defp normalize_status(status) when is_atom(status), do: status

  defp normalize_status(status) when is_binary(status) do
    Enum.find(Booking.statuses(), status, &(Atom.to_string(&1) == status))
  end

  defp filter_scope(rows, nil), do: rows
  defp filter_scope(rows, :all), do: rows

  defp filter_scope(rows, :upcoming) do
    rows
    |> Enum.filter(fn row ->
      case row.session do
        nil -> false
        session -> DateTime.compare(session.starts_at, now()) != :lt
      end
    end)
    |> Enum.sort_by(fn row -> row.session.starts_at end, DateTime)
  end

  defp filter_scope(rows, :past) do
    rows
    |> Enum.filter(fn row ->
      case row.session do
        nil -> booking_terminal?(row.booking)
        session -> DateTime.compare(session.ends_at, now()) == :lt
      end
    end)
    |> Enum.sort_by(
      fn row -> if(row.session, do: row.session.starts_at, else: row.booking.inserted_at) end,
      DateTime
    )
  end

  defp filter_scope(rows, _scope), do: rows

  defp booking_terminal?(%Booking{status: status}),
    do: status in [:cancelled, :attended, :no_show]

  defp enrich(bookings) do
    session_ids = bookings |> Enum.map(& &1.session_id) |> Enum.uniq() |> Enum.reject(&is_nil/1)
    sessions = Map.new(session_ids, fn id -> {id, safe_session(id)} end)
    offerings = Map.new(Catalog.list_offerings(), &{&1.id, &1})

    Enum.map(bookings, fn booking ->
      session = Map.get(sessions, booking.session_id)
      offering = session && Map.get(offerings, session.offering_id)
      %{booking: booking, session: session, offering: offering}
    end)
  end

  defp lock_booking(nil), do: nil

  defp lock_booking(booking_id) do
    Repo.one(from b in Booking, where: b.id == ^booking_id, lock: "FOR UPDATE")
  end

  defp lock_session(session_id) do
    {:ok, lock_session!(session_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp lock_session!(session_id), do: Seats.lock_session!(session_id)

  defp lock_sessions(ids) do
    sessions =
      ids
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&lock_session!/1)

    {:ok, Map.new(sessions, &{&1.id, &1})}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_player(player_id) do
    case Players.fetch_player(player_id) do
      {:ok, player} -> {:ok, player}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_offering(offering_id) do
    case Catalog.fetch_offering(offering_id) do
      {:ok, offering} -> {:ok, offering}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_offering_required(offering_id) do
    case fetch_offering(offering_id) do
      {:ok, offering} -> {:ok, offering}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp fetch_session_required(session_id) do
    case Scheduling.fetch_session(session_id) do
      {:ok, session} -> {:ok, session}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp safe_session(session_id) do
    case Scheduling.fetch_session(session_id) do
      {:ok, session} -> session
      _ -> nil
    end
  end

  defp coach_assigned?(%StaffActor{role: :coach} = actor, session_id) do
    case membership_id_for(actor) do
      nil ->
        false

      membership_id ->
        case Scheduling.session_detail(session_id) do
          {:ok, %{coaches: coaches}} -> Enum.any?(coaches, &(&1.id == membership_id))
          _ -> false
        end
    end
  end

  defp membership_id_for(%StaffActor{membership: %{id: id}}), do: id

  defp membership_id_for(%StaffActor{staff_user_id: staff_user_id})
       when is_binary(staff_user_id) do
    case SportsCoachBookings.Staff.get_active_membership(staff_user_id) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp membership_id_for(_actor), do: nil

  defp fetch_record(schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp normalize_method(method) when method in [:credits, :paid, :comp], do: method
  defp normalize_method("credits"), do: :credits
  defp normalize_method("paid"), do: :paid
  defp normalize_method("comp"), do: :comp
  defp normalize_method(_), do: nil

  defp staff_manager?(%StaffActor{role: role}) when role in [:owner, :admin], do: true
  defp staff_manager?(_actor), do: false

  defp actor_fields(%StaffActor{staff_user_id: id}), do: {"StaffActor", id}
  defp actor_fields(%CustomerActor{customer_user_id: id}), do: {"CustomerActor", id}
  defp actor_fields(_actor), do: {nil, nil}

  defp tenant_currency do
    case TenantContext.get_tenant() do
      %{currency: currency} when is_binary(currency) -> currency
      _ -> "CAD"
    end
  end

  defp fetch(container, key) when is_map(container) do
    Map.get(container, key) || Map.get(container, to_string(key))
  end

  defp fetch(container, key) when is_list(container), do: Keyword.get(container, key)
  defp fetch(_container, _key), do: nil

  defp number(value) when is_integer(value), do: value
  defp number(value) when is_float(value), do: value
  defp number(_value), do: nil

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp write(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
