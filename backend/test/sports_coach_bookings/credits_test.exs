defmodule SportsCoachBookings.CreditsTest do
  use SportsCoachBookings.DataCase, async: false
  use ExUnitProperties

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Credits.CreditLot
  alias SportsCoachBookings.Credits.OrderEventsSubscriber

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  describe "grant/3" do
    test "grants a package's credits, writes one entry, and publishes credits.granted once" do
      offering = insert(:offering)
      package = package([offering.id], %{credit_quantity: 5, validity_days: 30})
      household = Ecto.UUID.generate()
      line = Ecto.UUID.generate()

      assert {:ok, lot} = Credits.grant(household, package.id, line)
      assert lot.quantity_granted == 5
      assert lot.remaining == 5
      assert lot.eligible_offering_ids == [offering.id]
      assert lot.expires_at

      assert [entry] = Credits.list_ledger(household)
      assert entry.reason == :grant
      assert entry.delta == 5

      assert amounts(household) == [{offering.id, 5}]
      assert event_names() == ["credits.granted"]

      # Replaying the event must not grant again or re-emit.
      assert {:ok, replayed} = Credits.grant(household, package.id, line)
      assert replayed.id == lot.id

      assert Credits.balance(household) == [
               %{offering_id: offering.id, amount: 5, nearest_expiry: lot.expires_at}
             ]

      assert event_names() == ["credits.granted"]
    end

    test "a package with no eligible offerings is spendable on any offering" do
      package = package([], %{credit_quantity: 3})
      household = Ecto.UUID.generate()

      assert {:ok, lot} = Credits.grant(household, package.id, Ecto.UUID.generate())
      assert lot.eligible_offering_ids == []

      assert [%{offering_id: :any, amount: 3}] = Credits.balance(household)

      assert {:ok, [_entry]} =
               Credits.consume(household, Ecto.UUID.generate(), 2,
                 booking_id: Ecto.UUID.generate()
               )
    end

    test "an unknown package returns :package_not_found" do
      assert {:error, :package_not_found} =
               Credits.grant(Ecto.UUID.generate(), Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end

  describe "consume/4" do
    test "spends from the soonest-expiring eligible lot first" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, later} =
        Credits.grant_complimentary(nil, household, %{
          amount: 3,
          eligible_offering_ids: [offering.id],
          validity_days: 30
        })

      {:ok, sooner} =
        Credits.grant_complimentary(nil, household, %{
          amount: 3,
          eligible_offering_ids: [offering.id],
          validity_days: 1
        })

      assert {:ok, entries} = Credits.consume(household, offering.id, 4)
      assert Enum.map(entries, & &1.delta) == [-3, -1]

      assert Repo.get!(CreditLot, sooner.id).remaining == 0
      assert Repo.get!(CreditLot, later.id).remaining == 2
      assert amounts(household) == [{offering.id, 2}]
    end

    test "returns :insufficient_credits without writing when the balance is too low" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, _} =
        Credits.grant_complimentary(nil, household, %{
          amount: 1,
          eligible_offering_ids: [offering.id]
        })

      assert {:error, :insufficient_credits} = Credits.consume(household, offering.id, 2)

      assert amounts(household) == [{offering.id, 1}]
      assert length(Credits.list_ledger(household)) == 1
    end

    test "will not spend an offering-restricted lot on another offering" do
      offering = insert(:offering)
      other = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, _} =
        Credits.grant_complimentary(nil, household, %{
          amount: 3,
          eligible_offering_ids: [offering.id]
        })

      assert {:error, :insufficient_credits} = Credits.consume(household, other.id, 1)
    end

    test "is idempotent per booking" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()
      booking = Ecto.UUID.generate()

      {:ok, _} =
        Credits.grant_complimentary(nil, household, %{
          amount: 5,
          eligible_offering_ids: [offering.id]
        })

      assert {:ok, entries} = Credits.consume(household, offering.id, 2, booking_id: booking)
      assert {:ok, replayed} = Credits.consume(household, offering.id, 2, booking_id: booking)

      assert Enum.map(replayed, & &1.id) == Enum.map(entries, & &1.id)
      assert amounts(household) == [{offering.id, 3}]
    end

    test "only one of several attempts on the last credit succeeds" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, _} =
        Credits.grant_complimentary(nil, household, %{
          amount: 1,
          eligible_offering_ids: [offering.id]
        })

      results =
        for _ <- 1..5 do
          Repo.with_tenant_tx(fn ->
            Credits.consume(household, offering.id, 1, booking_id: Ecto.UUID.generate())
          end)
        end

      successes = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failures = Enum.count(results, &match?({:ok, {:error, :insufficient_credits}}, &1))

      assert successes == 1
      assert failures == 4
    end
  end

  describe "reverse/2" do
    test "returns credits to the original lot and is idempotent" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()
      booking = Ecto.UUID.generate()

      {:ok, lot} =
        Credits.grant_complimentary(nil, household, %{
          amount: 5,
          eligible_offering_ids: [offering.id]
        })

      assert {:ok, _} = Credits.consume(household, offering.id, 2, booking_id: booking)
      assert Repo.get!(CreditLot, lot.id).remaining == 3

      assert {:ok, %{amount: 2, entries: [reversal], grace_lots: []}} = Credits.reverse(booking)
      assert reversal.reason == :reversal
      assert reversal.delta == 2
      assert Repo.get!(CreditLot, lot.id).remaining == 5

      assert {:ok, %{amount: 0, entries: []}} = Credits.reverse(booking)
      assert Repo.get!(CreditLot, lot.id).remaining == 5
    end

    test "creates a return_grace lot when the original lot has expired" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()
      booking = Ecto.UUID.generate()

      {:ok, lot} =
        Credits.grant_complimentary(nil, household, %{
          amount: 3,
          eligible_offering_ids: [offering.id],
          validity_days: 1
        })

      assert {:ok, _} = Credits.consume(household, offering.id, 2, booking_id: booking)

      # Expire the lot behind the debit's back.
      past = DateTime.add(DateTime.utc_now(), -1, :day)
      Repo.update_all(from(l in CreditLot, where: l.id == ^lot.id), set: [expires_at: past])

      assert {:ok, %{amount: 2, grace_lots: [grace]}} = Credits.reverse(booking)
      assert grace.source == :return_grace
      assert grace.remaining == 2
      assert grace.eligible_offering_ids == [offering.id]
      assert DateTime.compare(grace.expires_at, DateTime.utc_now()) == :gt
      assert Repo.get!(CreditLot, lot.id).remaining == 1
    end
  end

  describe "expiry" do
    test "expiring a lot reduces the balance via a ledger entry and emits credits.expired" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, lot} =
        Credits.grant_complimentary(nil, household, %{
          amount: 4,
          eligible_offering_ids: [offering.id],
          validity_days: 1
        })

      past = DateTime.add(DateTime.utc_now(), -1, :day)
      Repo.update_all(from(l in CreditLot, where: l.id == ^lot.id), set: [expires_at: past])

      assert {:ok, [entry]} = Credits.expire_due_lots(DateTime.utc_now())
      assert entry.reason == :expire
      assert entry.delta == -4

      assert Repo.get!(CreditLot, lot.id).remaining == 0
      assert Credits.balance(household) == []
      assert event_names() == ["credits.expired"]

      # Idempotent.
      assert {:ok, []} = Credits.expire_due_lots(DateTime.utc_now())
      assert event_names() == ["credits.expired"]
    end

    test "emits credits.expiring_soon once per lot" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, _} =
        Credits.grant_complimentary(nil, household, %{
          amount: 2,
          eligible_offering_ids: [offering.id],
          validity_days: 3
        })

      assert {:ok, [notified]} = Credits.notify_expiring_soon(DateTime.utc_now(), 7)
      assert notified.expiring_soon_notified_at
      assert event_names() == ["credits.expiring_soon"]

      assert {:ok, []} = Credits.notify_expiring_soon(DateTime.utc_now(), 7)
      assert event_names() == ["credits.expiring_soon"]
    end

    test "a lot expiring beyond the window is not notified" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, _} =
        Credits.grant_complimentary(nil, household, %{
          amount: 2,
          eligible_offering_ids: [offering.id],
          validity_days: 30
        })

      assert {:ok, []} = Credits.notify_expiring_soon(DateTime.utc_now(), 7)
      assert event_names() == []
    end
  end

  describe "admin adjust" do
    test "adjusts a lot and records an audit event" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, lot} =
        Credits.grant_complimentary(nil, household, %{
          amount: 5,
          eligible_offering_ids: [offering.id]
        })

      actor = %SportsCoachBookings.Core.StaffActor{
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: TenantContext.get_tenant_id(),
        role: :owner
      }

      assert {:ok, adjusted} =
               Credits.adjust(actor, household, lot.id, %{"delta" => -2, "note" => "goodwill"})

      assert adjusted.remaining == 3

      assert {:ok, _} = Credits.adjust(actor, household, nil, %{"delta" => 4})

      assert amounts(household) == [{:any, 4}, {offering.id, 3}]

      actions =
        Repo.all(from a in SportsCoachBookings.Core.Audit.Event, select: a.action)

      assert "credits.credit.adjusted" in actions
      assert "credits.credit.granted" in actions
    end

    test "refuses to adjust below zero" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, lot} =
        Credits.grant_complimentary(nil, household, %{
          amount: 1,
          eligible_offering_ids: [offering.id]
        })

      assert {:error, :insufficient_credits} =
               Credits.adjust(nil, household, lot.id, %{"delta" => -2})
    end
  end

  describe "reconciliation and append-only" do
    test "reconcile reports the invariant holds across grant/consume/reverse/expire" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()
      booking = Ecto.UUID.generate()

      {:ok, lot} =
        Credits.grant_complimentary(nil, household, %{
          amount: 5,
          eligible_offering_ids: [offering.id]
        })

      {:ok, _} = Credits.consume(household, offering.id, 2, booking_id: booking)
      {:ok, _} = Credits.reverse(booking)

      past = DateTime.add(DateTime.utc_now(), -1, :day)
      Repo.update_all(from(l in CreditLot, where: l.id == ^lot.id), set: [expires_at: past])
      {:ok, _} = Credits.expire_due_lots(DateTime.utc_now())

      assert {:ok, 0} = Credits.reconcile(household)
    end

    test "raw SQL UPDATE and DELETE on the ledger are rejected" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      {:ok, _} =
        Credits.grant_complimentary(nil, household, %{
          amount: 1,
          eligible_offering_ids: [offering.id]
        })

      [entry] = Credits.list_ledger(household)
      dumped = Ecto.UUID.dump!(entry.id)

      assert_raise Postgrex.Error, fn ->
        Repo.query!("UPDATE credit_ledger_entries SET delta = 1 WHERE id = $1", [dumped])
      end

      assert_raise Postgrex.Error, fn ->
        Repo.query!("DELETE FROM credit_ledger_entries WHERE id = $1", [dumped])
      end
    end
  end

  describe "order.paid subscriber" do
    test "grants package credits idempotently" do
      offering = insert(:offering)
      package = package([offering.id], %{credit_quantity: 4})
      household = Ecto.UUID.generate()
      line = Ecto.UUID.generate()

      payload = %{
        "household_id" => household,
        "lines" => [%{"package_id" => package.id, "order_line_id" => line, "quantity" => 1}]
      }

      assert :ok = OrderEventsSubscriber.handle_event("order.paid", payload)
      assert :ok = OrderEventsSubscriber.handle_event("order.paid", payload)

      assert amounts(household) == [{offering.id, 4}]
      assert length(Credits.list_ledger(household)) == 1
      assert event_names() == ["credits.granted"]
    end

    test "ignores lines without a package" do
      assert :ok =
               OrderEventsSubscriber.handle_event("order.paid", %{
                 "household_id" => Ecto.UUID.generate(),
                 "lines" => [
                   %{
                     "variant_id" => Ecto.UUID.generate(),
                     "order_line_id" => Ecto.UUID.generate()
                   }
                 ]
               })

      assert event_names() == []
    end
  end

  describe "property: ledger invariant" do
    property "random grant/consume/reverse sequences never break the invariant" do
      offering = insert(:offering)
      household = Ecto.UUID.generate()

      check all(ops <- list_of(operation(), max_length: 15), max_runs: 40) do
        bookings =
          Enum.reduce(ops, %{}, fn op, bookings ->
            apply_operation(household, offering.id, op, bookings)
          end)

        _ = bookings

        # Force any lapsed credits to expire, then the ledger must still balance.
        {:ok, _} = Credits.expire_due_lots(DateTime.add(DateTime.utc_now(), 400, :day))
        assert {:ok, total} = Credits.reconcile(household)
        assert total >= 0

        lots = Repo.all(from(l in CreditLot, where: l.household_id == ^household))
        assert Enum.all?(lots, &(&1.remaining >= 0 and &1.remaining <= &1.quantity_granted))
        assert total == Enum.sum_by(Credits.list_ledger(household), & &1.delta)
      end
    end
  end

  defp apply_operation(household, offering_id, {:grant, amount}, bookings) do
    {:ok, _} =
      Credits.grant_complimentary(nil, household, %{
        amount: amount,
        eligible_offering_ids: [offering_id],
        validity_days: 1
      })

    bookings
  end

  defp apply_operation(household, offering_id, {:consume, slot, amount}, bookings) do
    booking = Map.get_lazy(bookings, slot, fn -> Ecto.UUID.generate() end)
    _ = Credits.consume(household, offering_id, amount, booking_id: booking)
    Map.put(bookings, slot, booking)
  end

  defp apply_operation(_household, _offering_id, {:reverse, slot}, bookings) do
    case Map.get(bookings, slot) do
      nil -> :ok
      booking -> Credits.reverse(booking)
    end

    bookings
  end

  defp operation do
    gen all(
          kind <- member_of([:grant, :consume, :reverse]),
          amount <- integer(1..3),
          slot <- integer(0..2)
        ) do
      case kind do
        :grant -> {:grant, amount}
        :consume -> {:consume, slot, amount}
        :reverse -> {:reverse, slot}
      end
    end
  end

  defp package(offering_ids, attrs) do
    {:ok, package} =
      Catalog.create_package(
        nil,
        Map.merge(
          %{
            name: "Pack #{System.unique_integer([:positive])}",
            credit_quantity: 5,
            price: 5000,
            offering_ids: offering_ids
          },
          attrs
        )
      )

    package
  end

  defp event_names do
    Repo.all(
      from(j in Oban.Job,
        where: j.queue == "events",
        select: j.args["name"],
        order_by: [asc: j.id]
      )
    )
  end

  defp amounts(household) do
    household
    |> Credits.balance()
    |> Enum.map(&{&1.offering_id, &1.amount})
    |> Enum.sort()
  end
end
