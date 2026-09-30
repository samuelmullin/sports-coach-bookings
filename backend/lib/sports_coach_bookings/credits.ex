defmodule SportsCoachBookings.Credits do
  @moduledoc """
  The household credit ledger. Owned by WP-12.

  Credits live in `credit_lots`; every movement is an append-only
  `credit_ledger_entries` row. The invariant is that a lot's cached `remaining`
  always equals the sum of its ledger entries, and that entries are never
  updated or deleted — only reversed by appending a new entry.

      Repo.with_tenant_tx(fn ->
        {:ok, entries} = Credits.consume(household_id, offering_id, 1, booking_id: booking.id)
      end)

  ## Balance

  `balance/1` returns `[%{offering_id: binary() | :any, amount: integer,
  nearest_expiry: DateTime.t() | nil}]`, grouped by eligibility scope. A lot
  restricted to exactly one offering is reported under that offering id; an
  unrestricted lot (and a lot restricted to several offerings) is reported under
  `:any`. The sum of `amount` across the list equals the sum of the household's
  ledger entries. Use `available_for_offering/2` when you need the exact amount
  spendable on one offering.

  ## Consuming

  `consume/4` selects eligible lots (`remaining > 0`, not expired, and either
  unrestricted or listing the offering), ordered by soonest expiry then grant
  time (FIFO, "best-fit by expiry"), locks them `FOR UPDATE`, and debits across
  lots as needed. It is idempotent per `:booking_id` (a replay returns the
  original debit entries). It returns `{:ok, [entry]}` or
  `{:error, :insufficient_credits}`. It must run inside the caller's
  transaction (it uses `Repo.with_tenant_tx/2`, which joins an open transaction
  as a savepoint).

  ## Reversing

  `reverse/2` appends a `reversal` entry for every debit of a booking and
  credits the original lot. If the original lot has already expired, a new
  `return_grace` lot is created (valid for `:credits_return_grace_days`, default
  14). It is idempotent per booking and returns
  `{:ok, %{entries: [...], grace_lots: [...], amount: n}}`.
  """

  import Ecto.Query

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.Policy
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Credits.CreditLedgerEntry
  alias SportsCoachBookings.Credits.CreditLot
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Repo

  @default_grace_days 14
  @default_expiring_soon_days 7

  ## Balance

  @doc """
  Returns the household's credit balance grouped by eligibility scope.

  See the moduledoc for the grouping rule. Always equal to the sum of the
  household's ledger entries.
  """
  @spec balance(binary()) :: [
          %{offering_id: binary() | :any, amount: integer(), nearest_expiry: DateTime.t() | nil}
        ]
  def balance(household_id) when is_binary(household_id) do
    read(fn ->
      Repo.all(from l in CreditLot, where: l.household_id == ^household_id)
      |> group_balance()
    end)
  end

  @doc """
  The exact number of credits spendable on `offering_id` right now.

  Unlike `balance/1` this expands multi-offering lots only for offerings they
  list, so it is the precise availability figure.
  """
  @spec available_for_offering(binary(), binary()) :: integer()
  def available_for_offering(household_id, offering_id)
      when is_binary(household_id) and is_binary(offering_id) do
    read(fn ->
      now = now()

      Repo.all(
        from l in CreditLot,
          where: l.household_id == ^household_id,
          where: l.remaining > 0,
          where: is_nil(l.expires_at) or l.expires_at > ^now,
          where:
            l.eligible_offering_ids == [] or
              fragment("? = ANY(?)", type(^offering_id, :binary_id), l.eligible_offering_ids)
      )
      |> Enum.sum_by(& &1.remaining)
    end)
  end

  ## Consuming

  @doc """
  Consumes `amount` credits for `offering_id` from the household's eligible lots.

  Options:

    * `:booking_id` — the idempotency key; a replay returns the original debits.
    * `:actor` — recorded on the ledger entries.
    * `:note` — recorded on the ledger entries.

  Returns `{:ok, [CreditLedgerEntry.t()]}` or `{:error, :insufficient_credits}`.
  """
  @spec consume(binary(), binary() | nil, pos_integer(), keyword() | map()) ::
          {:ok, [CreditLedgerEntry.t()]} | {:error, :insufficient_credits | term()}
  def consume(household_id, offering_id, amount, opts \\ [])

  def consume(household_id, offering_id, amount, opts)
      when is_binary(household_id) and is_integer(amount) and amount > 0 do
    booking_id = opt(opts, :booking_id)
    actor = opt(opts, :actor)
    note = opt(opts, :note)

    write(fn -> do_consume(household_id, offering_id, amount, booking_id, actor, note) end)
  end

  def consume(_household_id, _offering_id, _amount, _opts),
    do: {:error, {:invalid_amount, "Amount must be a positive integer"}}

  defp do_consume(household_id, offering_id, amount, booking_id, actor, note) do
    if booking_id, do: lock_booking(booking_id)

    case debits_for_booking(booking_id) do
      [] -> consume_from_lots(household_id, offering_id, amount, booking_id, actor, note)
      entries -> {:ok, entries}
    end
  end

  defp consume_from_lots(household_id, offering_id, amount, booking_id, actor, note) do
    now = now()
    lots = lock_eligible_lots(household_id, offering_id, now)

    if Enum.sum_by(lots, & &1.remaining) < amount do
      {:error, :insufficient_credits}
    else
      ctx = %{booking_id: booking_id, actor: actor, note: note}
      allocate(lots, amount, ctx, [])
    end
  end

  defp allocate([], _remaining, _ctx, acc), do: {:ok, Enum.reverse(acc)}

  defp allocate([lot | rest], remaining, ctx, acc) do
    take = min(lot.remaining, remaining)

    if take <= 0 do
      allocate(rest, remaining, ctx, acc)
    else
      allocate_from_lot(lot, rest, take, remaining, ctx, acc)
    end
  end

  defp allocate_from_lot(lot, rest, take, remaining, ctx, acc) do
    with {:ok, entry} <- insert_entry(lot, -take, :debit, ctx),
         {:ok, _lot} <- update_remaining(lot, lot.remaining - take) do
      continue_allocate(rest, remaining - take, ctx, [entry | acc])
    end
  end

  defp continue_allocate(_rest, 0, _ctx, acc), do: {:ok, Enum.reverse(acc)}
  defp continue_allocate(rest, left, ctx, acc), do: allocate(rest, left, ctx, acc)

  ## Reversing

  @doc """
  Returns the credits debited for `booking_id` to their original lots.

  Appends a `reversal` entry per debit (never mutates the debit). If the
  original lot has expired, a new `return_grace` lot is created instead.
  Idempotent: a replay returns the existing reversals.

  Options: `:actor`, `:note`.
  """
  @spec reverse(binary(), keyword() | map()) ::
          {:ok,
           %{entries: [CreditLedgerEntry.t()], grace_lots: [CreditLot.t()], amount: integer()}}
          | {:error, term()}
  def reverse(booking_id, opts \\ []) when is_binary(booking_id) do
    actor = opt(opts, :actor)
    note = opt(opts, :note)

    write(fn -> do_reverse(booking_id, actor, note) end)
  end

  defp do_reverse(booking_id, actor, note) do
    lock_booking(booking_id)
    debits = unreversed_debits(booking_id)
    locked = lock_lots(Enum.map(debits, & &1.credit_lot_id))

    {entries, grace_lots} =
      Enum.reduce(debits, {[], []}, fn debit, {entries, grace_lots} ->
        lot = Map.fetch!(locked, debit.credit_lot_id)
        {entry, grace} = reverse_debit(lot, debit, actor, note)

        {[entry | entries], if(grace, do: [grace | grace_lots], else: grace_lots)}
      end)

    {:ok,
     %{
       entries: Enum.reverse(entries),
       grace_lots: Enum.reverse(grace_lots),
       amount: Enum.sum_by(entries, & &1.delta)
     }}
  end

  defp reverse_debit(lot, debit, actor, note) do
    refund = -debit.delta
    now = now()

    if CreditLot.expired?(lot, now) do
      create_grace_lot(lot, debit, refund, actor, note, now)
    else
      ctx = %{
        booking_id: debit.booking_id,
        actor: actor,
        note: note,
        reverses_entry_id: debit.id
      }

      {:ok, entry} = insert_entry(lot, refund, :reversal, ctx)
      {:ok, _lot} = update_remaining(lot, lot.remaining + refund)
      {entry, nil}
    end
  end

  defp create_grace_lot(lot, debit, refund, actor, note, now) do
    grace =
      %CreditLot{}
      |> CreditLot.changeset(%{
        tenant_id: lot.tenant_id,
        household_id: lot.household_id,
        source: :return_grace,
        eligible_offering_ids: lot.eligible_offering_ids,
        quantity_granted: refund,
        remaining: refund,
        expires_at: DateTime.add(now, grace_days(), :day),
        granted_at: now
      })
      |> Repo.insert!()

    ctx = %{
      booking_id: debit.booking_id,
      actor: actor,
      note: note || "returned after expiry",
      reverses_entry_id: debit.id
    }

    {:ok, entry} = insert_entry(grace, refund, :reversal, ctx)
    {entry, grace}
  end

  ## Package grants

  @doc """
  Grants a purchased package's credits to a household.

  Idempotent on `order_line_id` (at most one lot per order line). Publishes
  `credits.granted` inside the transaction only when a lot is actually created.
  """
  @spec grant(binary(), binary(), binary() | nil, keyword() | map()) ::
          {:ok, CreditLot.t()} | {:error, :package_not_found | Ecto.Changeset.t()}
  def grant(household_id, package_id, order_line_id, opts \\ [])

  def grant(household_id, package_id, order_line_id, opts)
      when is_binary(household_id) and is_binary(package_id) do
    quantity = opt(opts, :quantity) || 1
    write(fn -> do_grant(household_id, package_id, order_line_id, max(quantity, 1)) end)
  end

  defp do_grant(household_id, package_id, order_line_id, quantity) do
    case order_line_lot(order_line_id) do
      %CreditLot{} = lot ->
        {:ok, lot}

      nil ->
        case Catalog.fetch_package(package_id) do
          {:error, :not_found} -> {:error, :package_not_found}
          {:ok, package} -> create_package_lot(household_id, package, order_line_id, quantity)
        end
    end
  end

  defp create_package_lot(household_id, package, order_line_id, quantity) do
    now = now()
    granted = package.credit_quantity * quantity

    lot =
      %CreditLot{}
      |> CreditLot.changeset(%{
        tenant_id: TenantContext.get_tenant_id(),
        household_id: household_id,
        source: :package_purchase,
        order_line_id: order_line_id,
        package_id: package.id,
        eligible_offering_ids: eligible_offerings(package.id),
        quantity_granted: granted,
        remaining: granted,
        expires_at: expiry_from(now, package.validity_days),
        granted_at: now
      })
      |> Repo.insert!()

    {:ok, _entry} = insert_entry(lot, granted, :grant, %{note: "package purchase"})

    {:ok, _job} =
      Events.publish("credits.granted", %{
        household_id: household_id,
        lot_id: lot.id,
        amount: granted,
        source: :package_purchase,
        tenant_id: lot.tenant_id
      })

    {:ok, lot}
  end

  defp eligible_offerings(package_id) do
    case Catalog.package_eligible_offering_ids(package_id) do
      :all -> []
      ids -> ids
    end
  end

  ## Admin grant / adjust

  @doc """
  Grants complimentary credits to a household as a new `admin_grant` lot.

  Admin-only; audited.
  """
  @spec grant_complimentary(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, CreditLot.t()} | {:error, term()}
  def grant_complimentary(actor, household_id, attrs) do
    with {:ok, amount} <- positive_amount(attrs) do
      write(fn ->
        lot = insert_admin_lot(actor, household_id, amount, attrs)
        _ = Audit.record(actor, "credits.credit.granted", lot, %{amount: amount})
        {:ok, lot}
      end)
    end
  end

  @doc """
  Adjusts a household's credits by a signed `delta`.

  With a `lot_id`, adjusts that lot (creating the matching ledger entry); with
  `nil` it creates a new `admin_grant` lot (delta must be positive). Admin-only;
  audited.
  """
  @spec adjust(Policy.actor(), binary(), binary() | nil, map() | keyword()) ::
          {:ok, CreditLot.t()} | {:error, term()}
  def adjust(actor, household_id, lot_id, attrs) do
    with {:ok, delta} <- nonzero_delta(attrs) do
      write(fn -> do_adjust(actor, household_id, lot_id, delta, attrs) end)
    end
  end

  defp do_adjust(actor, household_id, nil, delta, attrs) when delta > 0 do
    lot = insert_admin_lot(actor, household_id, delta, attrs)
    _ = Audit.record(actor, "credits.credit.granted", lot, %{amount: delta})
    {:ok, lot}
  end

  defp do_adjust(_actor, _household_id, nil, _delta, _attrs),
    do: {:error, {:invalid_delta, "A new lot requires a positive amount"}}

  defp do_adjust(actor, household_id, lot_id, delta, attrs) do
    case lock_lot(lot_id) do
      nil ->
        {:error, :not_found}

      %CreditLot{household_id: ^household_id} = lot ->
        apply_adjust(actor, lot, delta, attrs)

      %CreditLot{} ->
        {:error, :not_found}
    end
  end

  defp apply_adjust(actor, lot, delta, attrs) do
    new_remaining = lot.remaining + delta
    quantity = max(lot.quantity_granted, new_remaining)

    if new_remaining < 0 do
      {:error, :insufficient_credits}
    else
      ctx = %{actor: actor, note: opt(attrs, :note)}

      with {:ok, _entry} <- insert_entry(lot, delta, :adjust, ctx),
           {:ok, updated} <- persist(lot, %{remaining: new_remaining, quantity_granted: quantity}) do
        _ = Audit.record(actor, "credits.credit.adjusted", updated, %{delta: delta})
        {:ok, updated}
      end
    end
  end

  defp insert_admin_lot(actor, household_id, amount, attrs) do
    now = now()

    lot =
      %CreditLot{}
      |> CreditLot.changeset(%{
        tenant_id: TenantContext.get_tenant_id(),
        household_id: household_id,
        source: :admin_grant,
        eligible_offering_ids: eligible_ids_attr(attrs),
        quantity_granted: amount,
        remaining: amount,
        expires_at: expiry_from(now, opt(attrs, :validity_days)),
        granted_at: now
      })
      |> Repo.insert!()

    ctx = %{actor: actor, note: opt(attrs, :note)}
    {:ok, _entry} = insert_entry(lot, amount, :grant, ctx)
    lot
  end

  ## Revocation (order refunds)

  @doc "The number of unused credits still attached to an order line."
  @spec revocable_for(binary()) :: non_neg_integer()
  def revocable_for(order_line_id) when is_binary(order_line_id) do
    read(fn ->
      case order_line_lot(order_line_id) do
        %CreditLot{remaining: remaining} -> remaining
        nil -> 0
      end
    end)
  end

  @doc """
  Revokes the unused credits attached to a refunded order line.

  Admin-only (called by the `order.refunded` subscriber); audited. The used
  portion is not clawed back. Idempotent.
  """
  @spec revoke_unused(Policy.actor(), binary()) ::
          {:ok, %{revoked: non_neg_integer()}} | {:error, term()}
  def revoke_unused(actor, order_line_id) when is_binary(order_line_id) do
    write(fn -> do_revoke_unused(actor, order_line_id) end)
  end

  defp do_revoke_unused(actor, order_line_id) do
    case lock_order_line_lot(order_line_id) do
      nil -> {:ok, %{revoked: 0}}
      %CreditLot{remaining: 0} -> {:ok, %{revoked: 0}}
      %CreditLot{} = lot -> revoke_lot(actor, lot)
    end
  end

  defp revoke_lot(actor, lot) do
    amount = lot.remaining
    ctx = %{actor: actor, note: "order refunded"}

    with {:ok, _entry} <- insert_entry(lot, -amount, :adjust, ctx),
         {:ok, _lot} <- update_remaining(lot, 0) do
      _ = Audit.record(actor, "credits.credit.revoked", lot, %{amount: amount})
      {:ok, %{revoked: amount}}
    end
  end

  ## Expiry sweep (Oban)

  @doc """
  Expires every lot past `expires_at`, appending an `expire` entry and
  publishing `credits.expired`. Idempotent.
  """
  @spec expire_due_lots(DateTime.t()) :: {:ok, [CreditLedgerEntry.t()]} | {:error, term()}
  def expire_due_lots(now \\ DateTime.utc_now()) do
    write(fn -> do_expire_due_lots(now) end)
  end

  defp do_expire_due_lots(now) do
    lots =
      Repo.all(
        from l in CreditLot,
          where: l.remaining > 0,
          where: not is_nil(l.expires_at) and l.expires_at <= ^now,
          order_by: [asc: l.id],
          lock: "FOR UPDATE"
      )

    Enum.reduce_while(lots, {:ok, []}, fn lot, {:ok, acc} ->
      case expire_lot(lot) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      other -> other
    end
  end

  defp expire_lot(lot) do
    amount = lot.remaining
    ctx = %{note: "expired"}

    with {:ok, entry} <- insert_entry(lot, -amount, :expire, ctx),
         {:ok, _lot} <- update_remaining(lot, 0),
         {:ok, _job} <-
           Events.publish("credits.expired", %{
             household_id: lot.household_id,
             lot_id: lot.id,
             amount: amount,
             tenant_id: lot.tenant_id
           }) do
      {:ok, entry}
    end
  end

  @doc """
  Emits `credits.expiring_soon` once per lot expiring within `days` (default 7).
  """
  @spec notify_expiring_soon(DateTime.t(), pos_integer()) ::
          {:ok, [CreditLot.t()]} | {:error, term()}
  def notify_expiring_soon(now \\ DateTime.utc_now(), days \\ @default_expiring_soon_days) do
    write(fn -> do_notify_expiring_soon(now, days) end)
  end

  defp do_notify_expiring_soon(now, days) do
    deadline = DateTime.add(now, days, :day)

    lots =
      Repo.all(
        from l in CreditLot,
          where: l.remaining > 0,
          where: is_nil(l.expiring_soon_notified_at),
          where: not is_nil(l.expires_at) and l.expires_at > ^now and l.expires_at <= ^deadline,
          order_by: [asc: l.id],
          lock: "FOR UPDATE"
      )

    Enum.reduce_while(lots, {:ok, []}, fn lot, {:ok, acc} ->
      case notify_lot(lot, now) do
        {:ok, lot} -> {:cont, {:ok, [lot | acc]}}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, lots} -> {:ok, Enum.reverse(lots)}
      other -> other
    end
  end

  defp notify_lot(lot, now) do
    with {:ok, updated} <- persist(lot, %{expiring_soon_notified_at: now}),
         {:ok, _job} <-
           Events.publish("credits.expiring_soon", %{
             household_id: lot.household_id,
             lot_id: lot.id,
             amount: lot.remaining,
             expires_at: lot.expires_at,
             tenant_id: lot.tenant_id
           }) do
      {:ok, updated}
    end
  end

  ## Reads

  @doc "Fetches a lot, raising if it does not exist for this tenant."
  @spec get_lot!(binary()) :: CreditLot.t()
  def get_lot!(id), do: read(fn -> Repo.get!(CreditLot, id) end)

  @doc "Paginates a household's lots, newest first."
  @spec page_lots(binary(), map() | keyword()) ::
          %{data: [CreditLot.t()], next_cursor: binary() | nil}
  def page_lots(household_id, params \\ %{}) do
    paginate(from(l in CreditLot, where: l.household_id == ^household_id), params)
  end

  @doc "Lists a household's lots, newest first."
  @spec list_lots(binary()) :: [CreditLot.t()]
  def list_lots(household_id) do
    read(fn ->
      Repo.all(
        from l in CreditLot,
          where: l.household_id == ^household_id,
          order_by: [desc: l.granted_at, desc: l.id]
      )
    end)
  end

  @doc "Paginates a household's ledger entries, newest first."
  @spec page_ledger(binary(), map() | keyword()) ::
          %{data: [CreditLedgerEntry.t()], next_cursor: binary() | nil}
  def page_ledger(household_id, params \\ %{}) do
    paginate(
      from(e in CreditLedgerEntry, where: e.household_id == ^household_id),
      params
    )
  end

  @doc "Lists a household's ledger entries, newest first."
  @spec list_ledger(binary()) :: [CreditLedgerEntry.t()]
  def list_ledger(household_id) do
    read(fn ->
      Repo.all(
        from e in CreditLedgerEntry,
          where: e.household_id == ^household_id,
          order_by: [desc: e.inserted_at, desc: e.id]
      )
    end)
  end

  @doc """
  Checks the lot invariant for a household.

  Returns `{:ok, total}` when every lot's cached `remaining` equals the sum of
  its ledger entries, or `{:error, {:reconciliation_failed, mismatches}}`.
  """
  @spec reconcile(binary()) ::
          {:ok, integer()} | {:error, {:reconciliation_failed, [map()]}}
  def reconcile(household_id) when is_binary(household_id) do
    read(fn -> do_reconcile(household_id) end)
  end

  defp do_reconcile(household_id) do
    lots = Repo.all(from l in CreditLot, where: l.household_id == ^household_id)

    mismatches =
      for lot <- lots,
          ledger = ledger_sum(lot.id),
          ledger != lot.remaining do
        %{lot_id: lot.id, cached: lot.remaining, ledger: ledger}
      end

    if mismatches == [] do
      {:ok, Enum.sum_by(lots, & &1.remaining)}
    else
      {:error, {:reconciliation_failed, mismatches}}
    end
  end

  ## Private helpers

  defp group_balance([]), do: []

  defp group_balance(lots) do
    lots
    |> Enum.group_by(&scope_of/1)
    |> Enum.map(fn {scope, grouped} ->
      %{
        offering_id: scope,
        amount: Enum.sum_by(grouped, & &1.remaining),
        nearest_expiry: nearest_expiry(grouped)
      }
    end)
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.sort_by(&sort_key/1)
  end

  defp scope_of(%CreditLot{eligible_offering_ids: []}), do: :any
  defp scope_of(%CreditLot{eligible_offering_ids: [id]}), do: id
  defp scope_of(%CreditLot{eligible_offering_ids: _many}), do: :any

  defp nearest_expiry(lots) do
    lots
    |> Enum.map(& &1.expires_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(DateTime, fn -> nil end)
  end

  # Sort `:any` first, then offering ids by value for stable output.
  defp sort_key(%{offering_id: :any}), do: {0, ""}
  defp sort_key(%{offering_id: id}), do: {1, id}

  defp lock_eligible_lots(household_id, offering_id, now) do
    query =
      from l in CreditLot,
        where: l.household_id == ^household_id,
        where: l.remaining > 0,
        where: is_nil(l.expires_at) or l.expires_at > ^now,
        order_by: [asc_nulls_last: l.expires_at, asc: l.granted_at, asc: l.id],
        lock: "FOR UPDATE"

    query =
      if offering_id in [nil, :any] do
        query
      else
        from l in query,
          where:
            l.eligible_offering_ids == [] or
              fragment("? = ANY(?)", type(^offering_id, :binary_id), l.eligible_offering_ids)
      end

    Repo.all(query)
  end

  defp lock_lots([]), do: %{}

  defp lock_lots(lot_ids) do
    lot_ids
    |> Enum.uniq()
    |> Enum.sort()
    |> then(fn ids ->
      Repo.all(
        from(l in CreditLot, where: l.id in ^ids, order_by: [asc: l.id], lock: "FOR UPDATE")
      )
    end)
    |> Map.new(&{&1.id, &1})
  end

  defp lock_lot(lot_id) do
    Repo.one(from l in CreditLot, where: l.id == ^lot_id, lock: "FOR UPDATE")
  end

  defp lock_order_line_lot(order_line_id) do
    Repo.one(
      from l in CreditLot,
        where: l.order_line_id == ^order_line_id,
        order_by: [asc: l.id],
        limit: 1,
        lock: "FOR UPDATE"
    )
  end

  defp order_line_lot(nil), do: nil

  defp order_line_lot(order_line_id) do
    Repo.one(
      from l in CreditLot,
        where: l.order_line_id == ^order_line_id,
        order_by: [asc: l.id],
        limit: 1
    )
  end

  defp lock_booking(booking_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [booking_id])
    :ok
  end

  defp debits_for_booking(nil), do: []

  defp debits_for_booking(booking_id) do
    Repo.all(
      from e in CreditLedgerEntry,
        where: e.booking_id == ^booking_id and e.reason == :debit,
        order_by: [asc: e.inserted_at, asc: e.id]
    )
  end

  defp unreversed_debits(booking_id) do
    Repo.all(
      from e in CreditLedgerEntry,
        left_join: r in CreditLedgerEntry,
        on: r.reverses_entry_id == e.id,
        where: e.booking_id == ^booking_id and e.reason == :debit and is_nil(r.id),
        order_by: [asc: e.inserted_at, asc: e.id],
        select: e
    )
  end

  defp insert_entry(lot, delta, reason, ctx) do
    attrs = %{
      tenant_id: lot.tenant_id,
      credit_lot_id: lot.id,
      household_id: lot.household_id,
      delta: delta,
      reason: reason,
      booking_id: Map.get(ctx, :booking_id),
      reverses_entry_id: Map.get(ctx, :reverses_entry_id),
      note: Map.get(ctx, :note),
      actor_type: actor_type(ctx),
      actor_id: actor_id(ctx)
    }

    %CreditLedgerEntry{}
    |> CreditLedgerEntry.changeset(attrs)
    |> Repo.insert()
  end

  defp update_remaining(lot, remaining), do: persist(lot, %{remaining: remaining})

  defp persist(lot, changes) do
    lot |> Ecto.Changeset.change(changes) |> Repo.update()
  end

  defp ledger_sum(lot_id) do
    Repo.one(
      from e in CreditLedgerEntry,
        where: e.credit_lot_id == ^lot_id,
        select: coalesce(sum(e.delta), 0)
    )
  end

  defp actor_type(%{actor: %StaffActor{}}), do: "StaffActor"
  defp actor_type(%{actor: %CustomerActor{}}), do: "CustomerActor"
  defp actor_type(_), do: nil

  defp actor_id(%{actor: %StaffActor{staff_user_id: id}}), do: id
  defp actor_id(%{actor: %CustomerActor{customer_user_id: id}}), do: id
  defp actor_id(_), do: nil

  defp expiry_from(_now, nil), do: nil

  defp expiry_from(now, days) when is_integer(days) and days > 0,
    do: DateTime.add(now, days, :day)

  defp eligible_ids_attr(attrs) do
    case opt(attrs, :eligible_offering_ids) do
      ids when is_list(ids) -> ids
      _ -> []
    end
  end

  defp positive_amount(attrs) do
    case opt(attrs, :amount) || opt(attrs, :quantity) do
      amount when is_integer(amount) and amount > 0 ->
        {:ok, amount}

      _ ->
        {:error, {:invalid_amount, "Amount must be a positive integer"}}
    end
  end

  defp nonzero_delta(attrs) do
    case opt(attrs, :delta) do
      delta when is_integer(delta) and delta != 0 -> {:ok, delta}
      _ -> {:error, {:invalid_delta, "Delta must be a non-zero integer"}}
    end
  end

  defp grace_days do
    Application.get_env(:sports_coach_bookings, :credits_return_grace_days, @default_grace_days)
  end

  defp opt(opts, key) when is_map(opts) or is_list(opts) do
    converted = Enum.into(opts, %{})
    Map.get(converted, key) || Map.get(converted, to_string(key))
  end

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

  defp paginate(query, params) do
    read(fn ->
      {rows, next_cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: next_cursor}
    end)
  end
end
