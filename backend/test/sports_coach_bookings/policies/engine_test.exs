defmodule SportsCoachBookings.Policies.EngineTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Policies.Engine
  alias SportsCoachBookings.Policies.Rules

  @now ~U[2026-01-01 12:00:00.000000Z]

  defp snapshot(rules) do
    %{
      "policy_id" => "policy-1",
      "policy_version" => 3,
      "summary" => "Summary",
      "rules" => rules
    }
  end

  defp facts(overrides) do
    Map.merge(
      %{
        action: :cancel,
        session_starts_at: @now,
        now: @now,
        payment_method: :credits,
        amount_paid: nil,
        rebook_count: 0,
        target_offering_id: nil,
        source_offering_id: nil
      },
      Map.new(overrides)
    )
  end

  defp at(hours, overrides \\ []) do
    facts(
      Map.merge(
        %{session_starts_at: DateTime.add(@now, round(hours * 3600), :second)},
        Map.new(overrides)
      )
    )
  end

  defp paid(amount), do: Money.new(amount, "CAD")

  describe "cancel" do
    test "returns a full credit and full refund at or before 24 hours" do
      outcome =
        Engine.evaluate(
          snapshot(Rules.default_map()),
          at(30, payment_method: :paid, amount_paid: paid(5000))
        )

      assert outcome.allowed?
      assert outcome.credit_outcome == :return
      assert outcome.refund_amount == paid(5000)
      assert outcome.tier_matched == 0
    end

    test "boundary: exactly min_hours_before matches that tier" do
      tiers = [
        %{min_hours_before: 48, credit_outcome: :return, money_refund_pct: 100},
        %{min_hours_before: 24, credit_outcome: :return, money_refund_pct: 50},
        %{min_hours_before: 0, credit_outcome: :forfeit, money_refund_pct: 0}
      ]

      rules = Map.put(Rules.default_map(), "cancellation_tiers", tiers)

      assert Engine.evaluate(snapshot(rules), at(24)).tier_matched == 1

      assert Engine.evaluate(
               snapshot(rules),
               at(24, payment_method: :paid, amount_paid: paid(10_000))
             ).refund_amount ==
               paid(5000)

      assert Engine.evaluate(snapshot(rules), at(48)).tier_matched == 0
      assert Engine.evaluate(snapshot(rules), at(47.999)).tier_matched == 1
      assert Engine.evaluate(snapshot(rules), at(0)).tier_matched == 2
    end

    test "forfeits inside the last window for credits" do
      outcome = Engine.evaluate(snapshot(Rules.default_map()), at(2))

      assert outcome.allowed?
      assert outcome.credit_outcome == :forfeit
      assert outcome.refund_amount == nil
      assert outcome.tier_matched == 1
    end

    test "a past-session cancel falls back to the final tier" do
      outcome = Engine.evaluate(snapshot(Rules.default_map()), at(-3))
      assert outcome.tier_matched == 1
      assert outcome.credit_outcome == :forfeit
    end

    test "late_cancel_counts_as_no_show applies the no-show rule" do
      rules =
        Rules.default_map()
        |> Map.put("late_cancel_counts_as_no_show", true)
        |> Map.put("no_show", %{"credit_outcome" => "forfeit", "money_refund_pct" => 25})

      outcome =
        Engine.evaluate(snapshot(rules), at(6, payment_method: :paid, amount_paid: paid(4000)))

      assert outcome.credit_outcome == :forfeit
      assert outcome.refund_amount == paid(1000)
    end
  end

  describe "no_show" do
    test "uses the no-show rule and ignores the tiers" do
      outcome =
        Engine.evaluate(
          snapshot(Rules.default_map()),
          facts(action: :no_show, payment_method: :paid, amount_paid: paid(2000))
        )

      assert outcome.allowed?
      assert outcome.credit_outcome == :forfeit
      assert outcome.refund_amount == paid(0)
      assert outcome.tier_matched == nil
    end
  end

  describe "provider_cancel" do
    test "always returns credits, even if the rule says forfeit" do
      rules =
        Rules.default_map()
        |> Map.put("provider_cancelled", %{
          "credit_outcome" => "forfeit",
          "money_refund_pct" => 100
        })

      outcome =
        Engine.evaluate(
          snapshot(rules),
          facts(action: :provider_cancel, payment_method: :paid, amount_paid: paid(3000))
        )

      assert outcome.allowed?
      assert outcome.credit_outcome == :return
      assert outcome.refund_amount == paid(3000)
    end
  end

  describe "rebook" do
    test "is allowed at exactly the minimum hours before" do
      outcome = Engine.evaluate(snapshot(Rules.default_map()), at(12, action: :rebook))
      assert outcome.allowed?
      assert outcome.credit_outcome == nil
      assert outcome.tier_matched == nil
    end

    test "is denied too late" do
      outcome = Engine.evaluate(snapshot(Rules.default_map()), at(11.9, action: :rebook))
      refute outcome.allowed?
      assert outcome.reason == :rebook_too_late
    end

    test "is denied once the rebook limit is reached" do
      outcome =
        Engine.evaluate(snapshot(Rules.default_map()), at(24, action: :rebook, rebook_count: 2))

      refute outcome.allowed?
      assert outcome.reason == :rebook_limit_reached
    end

    test "is denied for a different offering when same_offering_only" do
      outcome =
        Engine.evaluate(
          snapshot(Rules.default_map()),
          at(24, action: :rebook, source_offering_id: "a", target_offering_id: "b")
        )

      refute outcome.allowed?
      assert outcome.reason == :rebook_offering_mismatch
    end

    test "is denied when rebooking is disabled" do
      rules =
        Rules.default_map()
        |> Map.put("rebook", %{
          "allowed" => false,
          "min_hours_before" => 0,
          "max_rebooks_per_booking" => nil,
          "same_offering_only" => true
        })

      outcome = Engine.evaluate(snapshot(rules), at(48, action: :rebook))
      refute outcome.allowed?
      assert outcome.reason == :rebook_not_allowed
    end
  end

  test "accepts string-keyed snapshots and facts" do
    decoded = snapshot(Rules.default_map()) |> Jason.encode!() |> Jason.decode!()

    result =
      Engine.evaluate(decoded, %{
        "action" => "cancel",
        "session_starts_at" => DateTime.add(@now, 30 * 3600, :second),
        "now" => @now,
        "payment_method" => "paid",
        "amount_paid" => %{"amount" => 1000, "currency" => "CAD"}
      })

    assert result.credit_outcome == :return
    assert result.refund_amount == paid(1000)
  end
end
