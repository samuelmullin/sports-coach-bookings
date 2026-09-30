defmodule SportsCoachBookings.Policies.Rules do
  @moduledoc """
  Embedded cancellation/rebooking rules. Owned by WP-10.

  Rules are stored on a `CancellationPolicy` as JSON (`jsonb`) and copied into
  the snapshot stored on every booking. The engine (`Policies.Engine`) evaluates
  a snapshot, so the snapshot must be self-contained: it carries the rules, the
  policy id, the policy version, and the customer-facing summary.

  ## Validation

  Cancellation tiers must be listed **strictly descending** by
  `min_hours_before` (no duplicates, no overlaps). Every percentage must be in
  `0..100`; credit outcomes are `:return` or `:forfeit` (credits are integers, so
  there are no partial credits).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SportsCoachBookings.Policies.Rules.OutcomeRule
  alias SportsCoachBookings.Policies.Rules.Rebook
  alias SportsCoachBookings.Policies.Rules.Tier

  @primary_key false
  embedded_schema do
    embeds_many :cancellation_tiers, Tier, on_replace: :delete
    embeds_one :no_show, OutcomeRule, on_replace: :update
    field :late_cancel_counts_as_no_show, :boolean, default: false
    embeds_one :rebook, Rebook, on_replace: :update
    embeds_one :provider_cancelled, OutcomeRule, on_replace: :update
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(rules, attrs) do
    rules
    |> cast(attrs, [:late_cancel_counts_as_no_show])
    |> cast_embed(:cancellation_tiers, required: true)
    |> cast_embed(:no_show, required: true)
    |> cast_embed(:rebook, required: true)
    |> cast_embed(:provider_cancelled, required: true)
    |> validate_tiers()
  end

  @doc """
  The sensible default rules seeded for a new tenant: 24 h full credit return,
  otherwise forfeit; rebooking allowed at least 12 h before, at most twice.
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      cancellation_tiers: [
        %Tier{min_hours_before: 24, credit_outcome: :return, money_refund_pct: 100},
        %Tier{min_hours_before: 0, credit_outcome: :forfeit, money_refund_pct: 0}
      ],
      no_show: %OutcomeRule{credit_outcome: :forfeit, money_refund_pct: 0},
      late_cancel_counts_as_no_show: false,
      rebook: %Rebook{
        allowed: true,
        min_hours_before: 12,
        max_rebooks_per_booking: 2,
        same_offering_only: true
      },
      provider_cancelled: %OutcomeRule{credit_outcome: :return, money_refund_pct: 100}
    }
  end

  @doc "The default rules as a JSON-serialisable map."
  @spec default_map() :: map()
  def default_map, do: default() |> to_map()

  @doc "The customer-facing summary seeded with the default policy."
  @spec default_summary() :: String.t()
  def default_summary do
    """
    Cancel at least 24 hours before your session to receive a full credit. \
    Cancellations made with less than 24 hours' notice are not eligible for a \
    credit. Rebooking is allowed up to 12 hours before the session, twice per \
    booking.
    """
  end

  @doc "Serialises rules (or a rules struct) to a JSON-safe map with string keys."
  @spec to_map(t() | nil) :: map()
  def to_map(nil), do: default_map()

  def to_map(%__MODULE__{} = rules) do
    %{
      "cancellation_tiers" => Enum.map(rules.cancellation_tiers || [], &tier_to_map/1),
      "no_show" => outcome_to_map(rules.no_show),
      "late_cancel_counts_as_no_show" => rules.late_cancel_counts_as_no_show == true,
      "rebook" => rebook_to_map(rules.rebook),
      "provider_cancelled" => outcome_to_map(rules.provider_cancelled)
    }
  end

  @doc """
  Reads the rules out of a snapshot (or a rules struct) into a plain map with
  atom keys and atom `credit_outcome`s. Missing keys fall back to defaults so the
  engine is total.
  """
  @spec from_snapshot(map() | t()) :: map()
  def from_snapshot(%__MODULE__{} = rules), do: to_plain(rules)

  def from_snapshot(snapshot) when is_map(snapshot) do
    rules = fetch(snapshot, :rules) || snapshot

    %{
      cancellation_tiers: normalize_tiers(fetch(rules, :cancellation_tiers) || []),
      no_show: normalize_outcome(fetch(rules, :no_show)),
      late_cancel_counts_as_no_show: fetch(rules, :late_cancel_counts_as_no_show) == true,
      rebook: normalize_rebook(fetch(rules, :rebook)),
      provider_cancelled: normalize_outcome(fetch(rules, :provider_cancelled))
    }
  end

  ## Private

  defp to_plain(%__MODULE__{} = rules) do
    rules
    |> to_map()
    |> from_snapshot()
  end

  defp validate_tiers(changeset) do
    case get_field(changeset, :cancellation_tiers) do
      nil ->
        add_error(changeset, :cancellation_tiers, "is required")

      [] ->
        add_error(changeset, :cancellation_tiers, "must contain at least one tier")

      tiers ->
        validate_tier_order(changeset, tiers)
    end
  end

  defp validate_tier_order(changeset, tiers) do
    hours = Enum.map(tiers, & &1.min_hours_before)

    if Enum.all?(hours, &is_integer/1) and
         (hours != Enum.sort(hours, :desc) or length(Enum.uniq(hours)) != length(hours)) do
      add_error(
        changeset,
        :cancellation_tiers,
        "must be ordered strictly descending by min_hours_before (no duplicates or overlaps)"
      )
    else
      changeset
    end
  end

  defp tier_to_map(%Tier{} = tier) do
    %{
      "min_hours_before" => tier.min_hours_before,
      "credit_outcome" => to_string(tier.credit_outcome),
      "money_refund_pct" => tier.money_refund_pct
    }
  end

  defp outcome_to_map(nil), do: %{"credit_outcome" => "forfeit", "money_refund_pct" => 0}

  defp outcome_to_map(%OutcomeRule{} = outcome) do
    %{
      "credit_outcome" => to_string(outcome.credit_outcome),
      "money_refund_pct" => outcome.money_refund_pct
    }
  end

  defp rebook_to_map(nil) do
    %{
      "allowed" => false,
      "min_hours_before" => 0,
      "max_rebooks_per_booking" => nil,
      "same_offering_only" => true
    }
  end

  defp rebook_to_map(%Rebook{} = rebook) do
    %{
      "allowed" => rebook.allowed == true,
      "min_hours_before" => rebook.min_hours_before,
      "max_rebooks_per_booking" => rebook.max_rebooks_per_booking,
      "same_offering_only" => rebook.same_offering_only == true
    }
  end

  defp normalize_tiers(tiers) when is_list(tiers), do: Enum.map(tiers, &normalize_tier/1)
  defp normalize_tiers(_), do: []

  defp normalize_tier(tier) when is_map(tier) do
    %{
      min_hours_before: fetch(tier, :min_hours_before) || 0,
      credit_outcome: outcome(fetch(tier, :credit_outcome)),
      money_refund_pct: fetch(tier, :money_refund_pct) || 0
    }
  end

  defp normalize_outcome(nil), do: %{credit_outcome: :forfeit, money_refund_pct: 0}

  defp normalize_outcome(outcome) when is_map(outcome) do
    %{
      credit_outcome: outcome(fetch(outcome, :credit_outcome)),
      money_refund_pct: fetch(outcome, :money_refund_pct) || 0
    }
  end

  defp normalize_rebook(nil) do
    %{allowed: false, min_hours_before: 0, max_rebooks_per_booking: nil, same_offering_only: true}
  end

  defp normalize_rebook(rebook) when is_map(rebook) do
    %{
      allowed: fetch(rebook, :allowed) == true,
      min_hours_before: fetch(rebook, :min_hours_before) || 0,
      max_rebooks_per_booking: fetch(rebook, :max_rebooks_per_booking),
      same_offering_only: fetch(rebook, :same_offering_only) == true
    }
  end

  defp outcome(:return), do: :return
  defp outcome("return"), do: :return
  defp outcome(:forfeit), do: :forfeit
  defp outcome("forfeit"), do: :forfeit
  defp outcome(_), do: :forfeit

  defp fetch(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
