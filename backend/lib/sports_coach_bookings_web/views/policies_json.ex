defmodule SportsCoachBookingsWeb.PoliciesJSON do
  @moduledoc "Serialises cancellation policies, snapshots, and outcomes."

  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Policies.CancellationPolicy
  alias SportsCoachBookings.Policies.OfferingPolicyAssignment
  alias SportsCoachBookings.Policies.Outcome
  alias SportsCoachBookings.Policies.Rules

  @doc "Serialises a cancellation policy."
  @spec policy(CancellationPolicy.t(), [binary()]) :: map()
  def policy(%CancellationPolicy{} = policy, offering_ids \\ []) do
    %{
      id: policy.id,
      name: policy.name,
      is_default: policy.is_default,
      version: policy.version,
      active: policy.active,
      customer_facing_summary: policy.customer_facing_summary,
      rules: Rules.to_map(policy.rules),
      assigned_offering_ids: offering_ids,
      inserted_at: datetime(policy.inserted_at),
      updated_at: datetime(policy.updated_at)
    }
  end

  @doc "Serialises an offering policy assignment."
  @spec assignment(OfferingPolicyAssignment.t()) :: map()
  def assignment(%OfferingPolicyAssignment{} = assignment) do
    %{
      id: assignment.id,
      offering_id: assignment.offering_id,
      cancellation_policy_id: assignment.cancellation_policy_id,
      inserted_at: datetime(assignment.inserted_at),
      updated_at: datetime(assignment.updated_at)
    }
  end

  @doc "Serialises the customer-facing summary for an offering."
  @spec summary(map()) :: map()
  def summary(summary) do
    %{
      offering_id: summary.offering_id,
      policy_id: summary.policy_id,
      policy_name: summary.policy_name,
      policy_version: summary.policy_version,
      summary: summary.summary
    }
  end

  @doc "Serialises a simulator result (`%{snapshot: …, outcome: …}`)."
  @spec simulation(%{snapshot: map(), outcome: Outcome.t()}) :: map()
  def simulation(%{snapshot: snapshot, outcome: outcome}) do
    %{
      snapshot: %{
        policy_id: snapshot["policy_id"],
        policy_name: snapshot["policy_name"],
        policy_version: snapshot["policy_version"],
        summary: snapshot["summary"]
      },
      outcome: outcome(outcome)
    }
  end

  @doc "Serialises an engine outcome."
  @spec outcome(Outcome.t()) :: map()
  def outcome(%Outcome{} = outcome) do
    %{
      allowed: outcome.allowed?,
      reason: stringify(outcome.reason),
      credit_outcome: stringify(outcome.credit_outcome),
      refund_amount: money(outcome.refund_amount),
      tier_matched: outcome.tier_matched
    }
  end

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp money(nil), do: nil
  defp money(%Money{} = money), do: Money.to_map(money)

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
