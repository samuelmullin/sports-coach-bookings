defmodule SportsCoachBookings.Catalog.PricingTest do
  use SportsCoachBookings.DataCase, async: false
  use ExUnitProperties

  alias SportsCoachBookings.Catalog.Pricing
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp money_line(type, ref, unit_price, opts \\ []) do
    %{
      type: type,
      ref_id: ref,
      unit_price: unit_price,
      quantity: Keyword.get(opts, :quantity, 1),
      taxable: Keyword.get(opts, :taxable, false)
    }
  end

  describe "without a discount" do
    test "returns zero discount and sums lines" do
      assert {:ok, result} =
               Pricing.price_lines(
                 [
                   money_line(:package, "a", 10_000),
                   money_line(:product, "b", 2_500, quantity: 2)
                 ],
                 nil,
                 nil
               )

      assert result.subtotal == 15_000
      assert result.discount_total == 0
      assert result.tax_total == 0
      assert result.total == 15_000
      assert result.discount == nil
    end
  end

  describe "percent discounts" do
    test "round half-up per line and keep the sum consistent" do
      insert(:discount, code: "TEN", kind: :percent, value: 1000, applies_to: :all)

      assert {:ok, result} =
               Pricing.price_lines(
                 [money_line(:package, "a", 999), money_line(:package, "b", 999)],
                 "TEN",
                 nil
               )

      assert result.discount_total == 100 + 100
      assert result.total == result.subtotal - result.discount_total
      assert Enum.sum(Enum.map(result.lines, & &1.line_total)) == result.total
    end

    test "never discounts more than the line subtotal" do
      insert(:discount, code: "FREE", kind: :percent, value: 20_000, applies_to: :all)

      assert {:ok, result} =
               Pricing.price_lines([money_line(:package, "a", 500)], "FREE", nil)

      assert result.discount_total == 500
      assert result.total == 0
    end
  end

  describe "fixed discounts" do
    test "allocates the amount across eligible lines without exceeding the subtotal" do
      insert(:discount, code: "FIVE", kind: :fixed, value: 5_000, applies_to: :all)

      assert {:ok, result} =
               Pricing.price_lines(
                 [money_line(:package, "a", 3_000), money_line(:package, "b", 7_000)],
                 "FIVE",
                 nil
               )

      assert result.discount_total == 5_000
      assert result.total == 5_000
    end

    test "caps a fixed discount at the eligible subtotal" do
      insert(:discount, code: "BIG", kind: :fixed, value: 1_000_000, applies_to: :all)

      assert {:ok, result} =
               Pricing.price_lines([money_line(:package, "a", 1_234)], "BIG", nil)

      assert result.discount_total == 1_234
      assert result.total == 0
    end
  end

  describe "tax" do
    test "applies the active rate to the discounted amount of taxable lines" do
      insert(:tax_rate, name: "HST", rate_bps: 1300, active: true)
      insert(:discount, code: "TEN", kind: :percent, value: 1000, applies_to: :all)

      assert {:ok, result} =
               Pricing.price_lines(
                 [
                   money_line(:package, "a", 10_000, taxable: true),
                   money_line(:product, "b", 5_000, taxable: false)
                 ],
                 "TEN",
                 nil
               )

      assert result.subtotal == 15_000
      assert result.discount_total == 1_500
      assert result.tax_total == 1_170
      assert result.total == 14_670
    end
  end

  describe "discount errors" do
    test "invalid_code when no such code exists" do
      assert {:error, :invalid_code} =
               Pricing.price_lines([money_line(:package, "a", 100)], "NOPE", nil)
    end

    test "expired when the window has passed" do
      insert(:discount, code: "OLD", ends_at: DateTime.add(DateTime.utc_now(), -3600))

      assert {:error, :expired} =
               Pricing.price_lines([money_line(:package, "a", 100)], "OLD", nil)
    end

    test "min_subtotal_not_met" do
      insert(:discount, code: "BIGMIN", applies_to: :all, min_subtotal: 10_000)

      assert {:error, :min_subtotal_not_met} =
               Pricing.price_lines([money_line(:package, "a", 100)], "BIGMIN", nil)
    end

    test "not_applicable when no line matches applies_to" do
      insert(:discount, code: "PROD", applies_to: :products)

      assert {:error, :not_applicable} =
               Pricing.price_lines([money_line(:package, "a", 100)], "PROD", nil)
    end

    test "exhausted when max_redemptions is reached" do
      discount = insert(:discount, code: "ONCE", max_redemptions: 1)

      Repo.with_tenant_tx(fn ->
        Pricing.record_redemption(discount.id, Ecto.UUID.generate(), Ecto.UUID.generate())
      end)

      assert {:error, :exhausted} =
               Pricing.price_lines([money_line(:package, "a", 100)], "ONCE", nil)
    end

    test "household_limit_reached" do
      discount = insert(:discount, code: "HH", per_household_limit: 1)
      household = Ecto.UUID.generate()

      Repo.with_tenant_tx(fn ->
        Pricing.record_redemption(discount.id, household, Ecto.UUID.generate())
      end)

      assert {:error, :household_limit_reached} =
               Pricing.price_lines([money_line(:package, "a", 100)], "HH", household)
    end
  end

  describe "record_redemption/3" do
    test "is idempotent for the same discount and order" do
      discount = insert(:discount)
      order = Ecto.UUID.generate()
      household = Ecto.UUID.generate()

      Repo.with_tenant_tx(fn -> Pricing.record_redemption(discount.id, household, order) end)
      Repo.with_tenant_tx(fn -> Pricing.record_redemption(discount.id, household, order) end)

      count =
        Repo.aggregate(
          from(r in SportsCoachBookings.Catalog.DiscountRedemption, where: r.order_id == ^order),
          :count
        )

      assert count == 1
    end
  end

  defp line_gen do
    gen all(
          type <- member_of([:package, :drop_in, :product]),
          unit_price <- integer(0..10_000),
          quantity <- integer(1..5),
          taxable <- boolean(),
          ref_id <- one_of([constant("ref-a"), constant("ref-b")])
        ) do
      %{type: type, ref_id: ref_id, unit_price: unit_price, quantity: quantity, taxable: taxable}
    end
  end

  describe "properties" do
    test "percent discount invariants hold" do
      insert(:tax_rate, name: "HST", rate_bps: 1300, active: true)
      insert(:discount, code: "PROP", kind: :percent, value: 1500, applies_to: :all)

      check all(lines <- list_of(line_gen(), min_length: 1, max_length: 5)) do
        {:ok, result} = Pricing.price_lines(lines, "PROP", nil)

        assert result.subtotal >= 0
        assert result.discount_total >= 0
        assert result.tax_total >= 0
        assert result.total >= 0
        assert result.discount_total <= result.subtotal
        assert Enum.all?(result.lines, &(&1.line_total >= 0))
        assert Enum.sum(Enum.map(result.lines, & &1.line_total)) == result.total
      end
    end

    test "fixed discount invariants hold" do
      insert(:tax_rate, name: "HST", rate_bps: 500, active: true)
      insert(:discount, code: "PROPFIX", kind: :fixed, value: 3_333, applies_to: :all)

      check all(lines <- list_of(line_gen(), min_length: 1, max_length: 5)) do
        {:ok, result} = Pricing.price_lines(lines, "PROPFIX", nil)

        assert result.discount_total >= 0
        assert result.discount_total <= result.subtotal
        assert result.total >= 0
        assert Enum.sum(Enum.map(result.lines, & &1.line_total)) == result.total
      end
    end

    test "pricing without a discount never exceeds subtotal" do
      check all(lines <- list_of(line_gen(), min_length: 1, max_length: 5)) do
        {:ok, result} = Pricing.price_lines(lines, nil, nil)

        assert result.discount_total == 0
        assert result.total == result.subtotal + result.tax_total
        assert Enum.sum(Enum.map(result.lines, & &1.line_total)) == result.total
      end
    end
  end
end
