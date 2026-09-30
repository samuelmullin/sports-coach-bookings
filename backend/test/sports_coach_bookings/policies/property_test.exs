defmodule SportsCoachBookings.Policies.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Policies.Engine
  alias SportsCoachBookings.Policies.Rules

  @now ~U[2026-01-01 12:00:00.000000Z]
  @thresholds [240, 120, 72, 48, 24, 12, 0]

  defp snapshot(rules) do
    %{"policy_id" => "p", "policy_version" => 1, "summary" => "s", "rules" => rules}
  end

  defp base_rules do
    Rules.default_map()
  end

  defp facts(hours, overrides) do
    Map.merge(
      %{
        action: :cancel,
        session_starts_at: DateTime.add(@now, round(hours * 3600), :second),
        now: @now,
        payment_method: :credits,
        amount_paid: nil,
        rebook_count: 0
      },
      Map.new(overrides)
    )
  end

  defp quality(%{credit_outcome: :return, refund_amount: refund}),
    do: {1, refund && refund.amount}

  defp quality(%{credit_outcome: :forfeit, refund_amount: refund}),
    do: {0, refund && refund.amount}

  property "cancelling earlier is never worse than cancelling later" do
    check all(
            pcts <- list_of(integer(0..100), min_length: 1, max_length: 7),
            h1 <- integer(0..300),
            h2 <- integer(0..300)
          ) do
      sorted = Enum.sort(pcts, :desc)

      tiers =
        sorted
        |> Enum.with_index()
        |> Enum.map(fn {pct, index} ->
          %{
            min_hours_before: Enum.at(@thresholds, index),
            credit_outcome: if(pct >= 50, do: :return, else: :forfeit),
            money_refund_pct: pct
          }
        end)

      rules = Map.put(base_rules(), "cancellation_tiers", tiers)
      money = Money.new(100_000, "CAD")

      early = max(h1, h2)
      late = min(h1, h2)

      early_outcome =
        Engine.evaluate(snapshot(rules), facts(early, payment_method: :paid, amount_paid: money))

      late_outcome =
        Engine.evaluate(snapshot(rules), facts(late, payment_method: :paid, amount_paid: money))

      assert quality(early_outcome) >= quality(late_outcome)
    end
  end

  property "a refund never exceeds the amount paid" do
    check all(
            amount <- integer(0..1_000_000),
            pct <- integer(0..100),
            hours <- integer(0..200),
            action <- member_of([:cancel, :no_show, :provider_cancel])
          ) do
      rule = %{"credit_outcome" => "return", "money_refund_pct" => pct}
      tier = %{"min_hours_before" => 0, "credit_outcome" => "return", "money_refund_pct" => pct}

      rules =
        base_rules()
        |> Map.put("cancellation_tiers", [tier])
        |> Map.put("no_show", rule)
        |> Map.put("provider_cancelled", rule)

      outcome =
        Engine.evaluate(
          snapshot(rules),
          facts(hours,
            action: action,
            payment_method: :paid,
            amount_paid: Money.new(amount, "CAD")
          )
        )

      if outcome.refund_amount do
        assert outcome.refund_amount.amount >= 0
        assert outcome.refund_amount.amount <= amount
      end
    end
  end

  property "the engine picks exactly the first matching tier" do
    check all(
            raw <- list_of(integer(0..240), min_length: 1, max_length: 6, uniq: true),
            hours <- integer(0..300)
          ) do
      thresholds = Enum.sort(raw, :desc)
      seconds = hours * 3600

      tiers =
        Enum.map(thresholds, fn threshold ->
          %{
            min_hours_before: threshold,
            credit_outcome: :return,
            money_refund_pct: 100
          }
        end)

      rules = Map.put(base_rules(), "cancellation_tiers", tiers)

      expected =
        Enum.find_index(thresholds, &(seconds >= &1 * 3600)) ||
          length(thresholds) - 1

      outcome = Engine.evaluate(snapshot(rules), facts(hours, []))

      assert outcome.tier_matched == expected
    end
  end

  property "provider_cancel always returns credits" do
    check all(
            credit_outcome <- member_of(["return", "forfeit"]),
            pct <- integer(0..100),
            hours <- integer(0..100)
          ) do
      rules =
        base_rules()
        |> Map.put("provider_cancelled", %{
          "credit_outcome" => credit_outcome,
          "money_refund_pct" => pct
        })

      outcome = Engine.evaluate(snapshot(rules), facts(hours, action: :provider_cancel))
      assert outcome.credit_outcome == :return
    end
  end
end
