defmodule SportsCoachBookings.Catalog.Pricing do
  @moduledoc """
  Pure-ish pricing over catalog inputs.

  `price_lines/3` takes cart-style lines plus an optional discount code and
  household, reads the current catalog rows (discount, its targets, redemptions,
  and the tenant's active tax rate), and returns per-line discount/tax/total
  figures.

  All amounts are integer minor units. Discounts and tax round half-up *per
  line*; tax is applied to the discounted amount.
  """

  import Ecto.Query

  alias SportsCoachBookings.Catalog.Discount
  alias SportsCoachBookings.Catalog.DiscountRedemption
  alias SportsCoachBookings.Catalog.DiscountTarget
  alias SportsCoachBookings.Catalog.TaxRate
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Repo

  @type line_type :: :package | :drop_in | :product

  @type line :: %{
          required(:type) => line_type() | String.t(),
          required(:ref_id) => binary(),
          required(:unit_price) => non_neg_integer(),
          optional(:quantity) => pos_integer(),
          optional(:taxable) => boolean(),
          optional(any()) => any()
        }

  @type priced_line :: %{
          type: line_type(),
          ref_id: binary(),
          unit_price: non_neg_integer(),
          quantity: pos_integer(),
          taxable: boolean(),
          amount: non_neg_integer(),
          discount_amount: non_neg_integer(),
          tax_amount: non_neg_integer(),
          line_total: non_neg_integer()
        }

  @type result :: %{
          lines: [priced_line()],
          discount: Discount.t() | nil,
          subtotal: non_neg_integer(),
          discount_total: non_neg_integer(),
          tax_total: non_neg_integer(),
          total: non_neg_integer()
        }

  @type error ::
          :invalid_code
          | :expired
          | :exhausted
          | :not_applicable
          | :min_subtotal_not_met
          | :household_limit_reached

  @doc """
  Prices `lines`, applying `discount_code` (or `nil`) for `household_id`.

  Returns `{:ok, result}` or `{:error, reason}` with one of the discount error
  atoms.
  """
  @spec price_lines([line()], String.t() | nil, binary() | nil) ::
          {:ok, result()} | {:error, error()}
  def price_lines(lines, discount_code \\ nil, household_id \\ nil) do
    normalized = Enum.map(lines, &normalize_line/1)

    Repo.with_tenant_tx(fn -> do_price_lines(normalized, discount_code, household_id) end)
    |> unwrap()
  end

  @doc """
  Records that `discount_id` was redeemed on `order_id` for `household_id`.

  Idempotent: replaying the same `(discount, order)` is a no-op. The caller is
  expected to run this inside the same transaction as the order write.
  """
  @spec record_redemption(binary(), binary(), binary()) ::
          {:ok, DiscountRedemption.t()} | {:error, Ecto.Changeset.t()}
  def record_redemption(discount_id, household_id, order_id) do
    attrs = %{
      tenant_id: tenant_id(),
      discount_id: discount_id,
      household_id: household_id,
      order_id: order_id
    }

    %DiscountRedemption{}
    |> DiscountRedemption.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:tenant_id, :discount_id, :order_id]
    )
  end

  defp do_price_lines(lines, discount_code, household_id) do
    subtotal = total_gross(lines)

    with {:ok, discount} <- find_discount(discount_code),
         :ok <- check_active(discount),
         :ok <- check_window(discount),
         :ok <- check_redemptions(discount, household_id),
         {:ok, eligible_indices} <- eligible_indices(discount, lines),
         :ok <- check_min_subtotal(discount, subtotal) do
      discounts = line_discounts(lines, eligible_indices, discount)
      rate = active_tax_rate_bps()

      priced =
        lines
        |> Enum.with_index()
        |> Enum.map(fn {line, index} ->
          build_priced_line(line, Enum.at(discounts, index), rate)
        end)

      discount_total = Enum.reduce(priced, 0, &(&1.discount_amount + &2))
      tax_total = Enum.reduce(priced, 0, &(&1.tax_amount + &2))
      total = Enum.reduce(priced, 0, &(&1.line_total + &2))

      {:ok,
       %{
         lines: priced,
         discount: discount,
         subtotal: subtotal,
         discount_total: discount_total,
         tax_total: tax_total,
         total: total
       }}
    end
  end

  ## Discount lookup and validation

  defp find_discount(nil), do: {:ok, nil}
  defp find_discount(""), do: {:ok, nil}

  defp find_discount(code) when is_binary(code) do
    case Repo.one(from d in Discount, where: d.code == ^code, limit: 1) do
      nil -> {:error, :invalid_code}
      discount -> {:ok, discount}
    end
  end

  defp check_active(nil), do: :ok
  defp check_active(%Discount{active: true}), do: :ok
  defp check_active(%Discount{}), do: {:error, :invalid_code}

  defp check_window(nil), do: :ok

  defp check_window(%Discount{starts_at: starts_at, ends_at: ends_at}) do
    now = DateTime.utc_now()

    cond do
      not is_nil(starts_at) and DateTime.compare(now, starts_at) == :lt -> {:error, :expired}
      not is_nil(ends_at) and DateTime.compare(now, ends_at) == :gt -> {:error, :expired}
      true -> :ok
    end
  end

  defp check_redemptions(nil, _household_id), do: :ok

  defp check_redemptions(%Discount{max_redemptions: max} = discount, household_id)
       when is_integer(max) do
    if redemption_count(discount.id) >= max do
      {:error, :exhausted}
    else
      check_household_limit(discount, household_id)
    end
  end

  defp check_redemptions(%Discount{} = discount, household_id) do
    check_household_limit(discount, household_id)
  end

  defp check_household_limit(%Discount{per_household_limit: limit, id: id}, household_id)
       when is_integer(limit) and is_binary(household_id) do
    if household_redemption_count(id, household_id) >= limit do
      {:error, :household_limit_reached}
    else
      :ok
    end
  end

  defp check_household_limit(_discount, _household_id), do: :ok

  defp check_min_subtotal(nil, _subtotal), do: :ok
  defp check_min_subtotal(%Discount{min_subtotal: nil}, _subtotal), do: :ok

  defp check_min_subtotal(%Discount{min_subtotal: min}, subtotal) when subtotal < min do
    {:error, :min_subtotal_not_met}
  end

  defp check_min_subtotal(_discount, _subtotal), do: :ok

  ## Eligibility

  defp eligible_indices(nil, _lines), do: {:ok, []}

  defp eligible_indices(%Discount{} = discount, lines) do
    targets = Repo.all(from t in DiscountTarget, where: t.discount_id == ^discount.id)

    indices =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _index} ->
        applies_to?(discount, line) and target_matches?(targets, line)
      end)
      |> Enum.map(&elem(&1, 1))

    if indices == [] do
      {:error, :not_applicable}
    else
      {:ok, indices}
    end
  end

  defp applies_to?(%Discount{applies_to: :all}, _line), do: true
  defp applies_to?(%Discount{applies_to: :packages}, %{type: :package}), do: true
  defp applies_to?(%Discount{applies_to: :drop_ins}, %{type: :drop_in}), do: true
  defp applies_to?(%Discount{applies_to: :products}, %{type: :product}), do: true
  defp applies_to?(_discount, _line), do: false

  defp target_matches?([], _line), do: true

  defp target_matches?(targets, line) do
    Enum.any?(targets, fn target ->
      target.target_id == line.ref_id and target_type?(target.target_type, line.type)
    end)
  end

  defp target_type?(:package, :package), do: true
  defp target_type?(:offering, :drop_in), do: true
  defp target_type?(:product, :product), do: true
  defp target_type?(_target_type, _line_type), do: false

  ## Discount math

  defp line_discounts(_lines, _indices, nil), do: []

  defp line_discounts(lines, indices, %Discount{kind: :percent, value: bps}) do
    eligible = MapSet.new(indices)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      if MapSet.member?(eligible, index) do
        min(gross(line), round_half_up(gross(line) * bps, 10_000))
      else
        0
      end
    end)
  end

  defp line_discounts(lines, indices, %Discount{kind: :fixed, value: amount}) do
    eligible_grosses = indices |> Enum.map(&gross(Enum.at(lines, &1)))
    allocations = allocate_fixed(amount, eligible_grosses)
    allocation_by_index = indices |> Enum.zip(allocations) |> Map.new()

    lines
    |> Enum.with_index()
    |> Enum.map(fn {_line, index} -> Map.get(allocation_by_index, index, 0) end)
  end

  defp allocate_fixed(_amount, []), do: []

  defp allocate_fixed(amount, grosses) do
    total = Enum.sum(grosses)

    if total == 0 do
      List.duplicate(0, length(grosses))
    else
      amount = min(amount, total)

      {allocations, _state} =
        Enum.map_reduce(grosses, {0, 0}, fn gross, {cum_gross, cum_alloc} ->
          cum_gross = cum_gross + gross
          target = round_half_up(amount * cum_gross, total)
          discount = target - cum_alloc
          discount = discount |> max(0) |> min(gross)
          {discount, {cum_gross, cum_alloc + discount}}
        end)

      allocations
    end
  end

  ## Tax

  defp active_tax_rate_bps do
    Repo.one(from t in TaxRate, where: t.active == true, select: t.rate_bps, limit: 1) || 0
  end

  defp build_priced_line(line, discount_amount, rate) do
    discount_amount = min(discount_amount || 0, gross(line))
    discounted = gross(line) - discount_amount

    tax_amount =
      if line.taxable and rate > 0 do
        round_half_up(discounted * rate, 10_000)
      else
        0
      end

    Map.merge(line, %{
      discount_amount: discount_amount,
      tax_amount: tax_amount,
      line_total: discounted + tax_amount
    })
  end

  ## Helpers

  defp normalize_line(line) do
    quantity = fetch(line, :quantity) || 1
    unit_price = fetch(line, :unit_price)

    %{
      type: normalize_type(fetch(line, :type)),
      ref_id: fetch(line, :ref_id),
      unit_price: unit_price,
      quantity: quantity,
      taxable: fetch(line, :taxable) || false,
      amount: unit_price * quantity
    }
  end

  defp normalize_type(type) when type in [:package, :drop_in, :product], do: type
  defp normalize_type("package"), do: :package
  defp normalize_type("drop_in"), do: :drop_in
  defp normalize_type("product"), do: :product
  defp normalize_type("drop-in"), do: :drop_in
  defp normalize_type(other), do: other

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp gross(%{amount: amount}), do: amount

  defp total_gross(lines), do: Enum.reduce(lines, 0, &(gross(&1) + &2))

  defp redemption_count(discount_id) do
    Repo.one(
      from r in DiscountRedemption,
        where: r.discount_id == ^discount_id,
        select: count(r.id)
    )
  end

  defp household_redemption_count(discount_id, household_id) do
    Repo.one(
      from r in DiscountRedemption,
        where: r.discount_id == ^discount_id and r.household_id == ^household_id,
        select: count(r.id)
    )
  end

  defp round_half_up(value, divisor) do
    quotient = div(value, divisor)
    remainder = rem(value, divisor)

    if remainder * 2 >= divisor do
      quotient + 1
    else
      quotient
    end
  end

  defp tenant_id, do: TenantContext.get_tenant_id()

  defp unwrap({:ok, result}), do: result
  defp unwrap({:error, reason}), do: {:error, reason}
end
