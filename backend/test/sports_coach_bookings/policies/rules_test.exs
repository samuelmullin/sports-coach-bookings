defmodule SportsCoachBookings.Policies.RulesTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias SportsCoachBookings.Policies.Rules

  defp valid_attrs(overrides) do
    Map.merge(Rules.default_map(), Map.new(overrides))
  end

  defp messages(changeset, field) do
    changeset.errors
    |> Enum.filter(fn {key, _} -> key == field end)
    |> Enum.map(fn {_, {message, _}} -> message end)
  end

  test "the default rules are valid" do
    changeset = Rules.changeset(%Rules{}, Rules.default_map())
    assert changeset.valid?
    assert length(get_field(changeset, :cancellation_tiers)) == 2
  end

  test "accepts boundary percentages 0 and 100" do
    attrs =
      valid_attrs(%{
        "cancellation_tiers" => [
          %{"min_hours_before" => 24, "credit_outcome" => "return", "money_refund_pct" => 100},
          %{"min_hours_before" => 0, "credit_outcome" => "forfeit", "money_refund_pct" => 0}
        ]
      })

    assert Rules.changeset(%Rules{}, attrs).valid?
  end

  test "rejects ascending (unordered) tiers" do
    attrs =
      valid_attrs(%{
        "cancellation_tiers" => [
          %{"min_hours_before" => 0, "credit_outcome" => "forfeit", "money_refund_pct" => 0},
          %{"min_hours_before" => 24, "credit_outcome" => "return", "money_refund_pct" => 100}
        ]
      })

    changeset = Rules.changeset(%Rules{}, attrs)
    refute changeset.valid?

    assert Enum.any?(
             messages(changeset, :cancellation_tiers),
             &(&1 =~ "ordered strictly descending")
           )
  end

  test "rejects duplicate / overlapping thresholds" do
    attrs =
      valid_attrs(%{
        "cancellation_tiers" => [
          %{"min_hours_before" => 24, "credit_outcome" => "return", "money_refund_pct" => 100},
          %{"min_hours_before" => 24, "credit_outcome" => "forfeit", "money_refund_pct" => 0}
        ]
      })

    changeset = Rules.changeset(%Rules{}, attrs)
    refute changeset.valid?

    assert Enum.any?(
             messages(changeset, :cancellation_tiers),
             &(&1 =~ "ordered strictly descending")
           )
  end

  test "rejects an empty tier list" do
    changeset = Rules.changeset(%Rules{}, valid_attrs(%{"cancellation_tiers" => []}))
    refute changeset.valid?
    assert Enum.any?(messages(changeset, :cancellation_tiers), &(&1 =~ "at least one tier"))
  end

  test "rejects a percentage above 100" do
    attrs =
      valid_attrs(%{
        "cancellation_tiers" => [
          %{"min_hours_before" => 0, "credit_outcome" => "return", "money_refund_pct" => 150}
        ]
      })

    refute Rules.changeset(%Rules{}, attrs).valid?
  end

  test "rejects a negative percentage" do
    attrs =
      valid_attrs(%{
        "cancellation_tiers" => [
          %{"min_hours_before" => 0, "credit_outcome" => "return", "money_refund_pct" => -1}
        ]
      })

    refute Rules.changeset(%Rules{}, attrs).valid?
  end

  test "rejects an unknown credit outcome" do
    attrs =
      valid_attrs(%{
        "cancellation_tiers" => [
          %{"min_hours_before" => 0, "credit_outcome" => "maybe", "money_refund_pct" => 0}
        ]
      })

    refute Rules.changeset(%Rules{}, attrs).valid?
  end

  test "to_map/from_snapshot round-trips through JSON" do
    decoded = Rules.default_map() |> Jason.encode!() |> Jason.decode!()
    plain = Rules.from_snapshot(decoded)

    assert [%{min_hours_before: 24, credit_outcome: :return, money_refund_pct: 100} | _] =
             plain.cancellation_tiers

    assert plain.no_show.credit_outcome == :forfeit
    assert plain.rebook.allowed
    assert plain.rebook.min_hours_before == 12
  end
end
