defmodule SportsCoachBookings.Policies.Engine do
  @moduledoc """
  The pure cancellation/rebooking engine. Owned by WP-10.

  `evaluate/2` takes a policy **snapshot** (the JSON-serialisable map stored on a
  booking) and a map of facts, and returns an `Outcome`. It performs no database
  access, reads no clock, and uses no tenant context — all time maths is in UTC
  and the current time is injected as `facts.now`.

  ## Facts

      %{
        action: :cancel | :rebook | :no_show | :provider_cancel,
        session_starts_at: DateTime.t(),
        now: DateTime.t(),
        payment_method: :credits | :paid,
        amount_paid: Money.t() | nil,
        rebook_count: non_neg_integer(),
        target_offering_id: binary() | nil,
        source_offering_id: binary() | nil
      }

  String or atom keys are accepted, so facts built from JSON work too.
  """

  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Policies.Outcome
  alias SportsCoachBookings.Policies.Rules

  @type facts :: %{
          optional(:action) => atom() | String.t(),
          optional(:session_starts_at) => DateTime.t(),
          optional(:now) => DateTime.t(),
          optional(:payment_method) => atom() | String.t(),
          optional(:amount_paid) => Money.t() | map() | nil,
          optional(:rebook_count) => non_neg_integer(),
          optional(:target_offering_id) => binary() | nil,
          optional(:source_offering_id) => binary() | nil
        }

  @doc """
  Evaluates `snapshot` against `facts` and returns the resulting `Outcome`.
  """
  @spec evaluate(map(), facts()) :: Outcome.t()
  def evaluate(snapshot, facts) do
    rules = Rules.from_snapshot(snapshot)
    seconds = seconds_before_start(facts)

    case normalize_action(fetch(facts, :action)) do
      :cancel -> evaluate_cancel(rules, facts, seconds)
      :no_show -> evaluate_no_show(rules, facts)
      :provider_cancel -> evaluate_provider_cancel(rules, facts)
      :rebook -> evaluate_rebook(rules, facts, seconds)
    end
  end

  @doc """
  True when a cancellation at `seconds_before` (UTC seconds until the session
  starts) counts as a late cancellation under `rules`.
  """
  @spec late_cancel?(list(), integer()) :: boolean()
  def late_cancel?(tiers, seconds_before) do
    positive = tiers |> Enum.map(& &1.min_hours_before) |> Enum.filter(&(&1 > 0))
    threshold = if positive == [], do: 0, else: Enum.min(positive)
    seconds_before < threshold * 3600
  end

  ## Actions

  defp evaluate_cancel(rules, facts, seconds) do
    {tier, index} = pick_tier(rules.cancellation_tiers, seconds)

    rule =
      if rules.late_cancel_counts_as_no_show and
           late_cancel?(rules.cancellation_tiers, seconds) do
        rules.no_show
      else
        tier
      end

    %Outcome{
      allowed?: true,
      reason: nil,
      credit_outcome: rule.credit_outcome,
      refund_amount: refund(facts, rule.money_refund_pct),
      tier_matched: index
    }
  end

  defp evaluate_no_show(rules, facts) do
    %Outcome{
      allowed?: true,
      reason: nil,
      credit_outcome: rules.no_show.credit_outcome,
      refund_amount: refund(facts, rules.no_show.money_refund_pct),
      tier_matched: nil
    }
  end

  defp evaluate_provider_cancel(rules, facts) do
    # When the tenant cancels the session, credits are always returned; the
    # policy only controls the money-refund percentage.
    %Outcome{
      allowed?: true,
      reason: nil,
      credit_outcome: :return,
      refund_amount: refund(facts, rules.provider_cancelled.money_refund_pct),
      tier_matched: nil
    }
  end

  defp evaluate_rebook(rules, facts, seconds) do
    rebook = rules.rebook

    cond do
      rebook.allowed != true -> denied(:rebook_not_allowed)
      rebook_too_late?(rebook, seconds) -> denied(:rebook_too_late)
      rebook_limit_reached?(rebook, facts) -> denied(:rebook_limit_reached)
      rebook_offering_mismatch?(rebook, facts) -> denied(:rebook_offering_mismatch)
      true -> %Outcome{allowed?: true, reason: nil}
    end
  end

  defp rebook_too_late?(rebook, seconds), do: seconds < rebook.min_hours_before * 3600

  defp rebook_limit_reached?(rebook, facts) do
    not is_nil(rebook.max_rebooks_per_booking) and
      (fetch(facts, :rebook_count) || 0) >= rebook.max_rebooks_per_booking
  end

  defp rebook_offering_mismatch?(rebook, facts) do
    target = fetch(facts, :target_offering_id)

    rebook.same_offering_only and not is_nil(target) and
      target != fetch(facts, :source_offering_id)
  end

  ## Helpers

  defp denied(reason), do: %Outcome{allowed?: false, reason: reason}

  defp pick_tier([], _seconds), do: {%{credit_outcome: :forfeit, money_refund_pct: 0}, nil}

  defp pick_tier(tiers, seconds) do
    index =
      Enum.find_index(tiers, fn tier -> seconds >= tier.min_hours_before * 3600 end) ||
        length(tiers) - 1

    {Enum.at(tiers, index), index}
  end

  defp seconds_before_start(facts) do
    starts = fetch(facts, :session_starts_at)
    now = fetch(facts, :now)

    case {starts, now} do
      {%DateTime{} = starts, %DateTime{} = now} -> DateTime.diff(starts, now, :second)
      _ -> 0
    end
  end

  defp refund(facts, pct) do
    if normalize_payment(fetch(facts, :payment_method)) == :paid do
      case money(fetch(facts, :amount_paid)) do
        nil -> nil
        amount -> Money.percent(amount, pct)
      end
    end
  end

  defp normalize_payment(:paid), do: :paid
  defp normalize_payment("paid"), do: :paid
  defp normalize_payment(_), do: :credits

  defp normalize_action(:cancel), do: :cancel
  defp normalize_action("cancel"), do: :cancel
  defp normalize_action(:rebook), do: :rebook
  defp normalize_action("rebook"), do: :rebook
  defp normalize_action(:no_show), do: :no_show
  defp normalize_action("no_show"), do: :no_show
  defp normalize_action(:provider_cancel), do: :provider_cancel
  defp normalize_action("provider_cancel"), do: :provider_cancel
  defp normalize_action(_), do: :cancel

  defp money(%Money{} = money), do: money
  defp money(%{"amount" => amount, "currency" => currency}), do: Money.new(amount, currency)
  defp money(%{amount: amount, currency: currency}), do: Money.new(amount, currency)
  defp money(_), do: nil

  defp fetch(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
