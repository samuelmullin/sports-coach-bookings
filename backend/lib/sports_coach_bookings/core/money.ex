defmodule SportsCoachBookings.Core.Money do
  @moduledoc """
  Money as an integer amount in minor units (cents) plus an ISO-4217 currency.

  Never use floats for money. All arithmetic requires matching currencies and
  raises `ArgumentError` otherwise. Rounding helpers use half-up semantics.
  """

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: integer(), currency: String.t()}

  @doc "Builds money from an integer minor-unit amount and a currency."
  @spec new(integer(), String.t()) :: t()
  def new(amount, currency) when is_integer(amount) and is_binary(currency) do
    %__MODULE__{amount: amount, currency: String.upcase(currency)}
  end

  @doc "Builds money or raises for invalid input."
  @spec new!(integer(), String.t()) :: t()
  def new!(amount, currency), do: new(amount, currency)

  @doc "The zero amount for a currency."
  @spec zero(String.t()) :: t()
  def zero(currency), do: new(0, currency)

  @doc "Adds two amounts of the same currency."
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{amount: a, currency: c} = left, %__MODULE__{amount: b, currency: c}) do
    %{left | amount: a + b}
  end

  def add(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError, "cannot add #{c1} and #{c2}"
  end

  @doc "Subtracts `right` from `left`."
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{} = left, %__MODULE__{} = right), do: add(left, negate(right))

  @doc "Negates an amount."
  @spec negate(t()) :: t()
  def negate(%__MODULE__{amount: a, currency: c}), do: new(-a, c)

  @doc "Multiplies an amount by an integer quantity."
  @spec multiply(t(), integer()) :: t()
  def multiply(%__MODULE__{amount: a, currency: c}, quantity) when is_integer(quantity) do
    new(a * quantity, c)
  end

  @doc """
  Applies a rate given in basis points (1 bps = 0.01%), rounding half-up to the
  minor unit.
  """
  @spec apply_bps(t(), integer()) :: t()
  def apply_bps(%__MODULE__{amount: a, currency: c}, bps) when is_integer(bps) do
    new(round_half_up(a * bps, 10_000), c)
  end

  @doc "Applies a percentage given as a whole number (e.g. 15 for 15%)."
  @spec percent(t(), number()) :: t()
  def percent(%__MODULE__{amount: a, currency: c}, pct) when is_number(pct) do
    new(round_half_up(round(a * pct * 100), 10_000), c)
  end

  @doc "Compares two amounts, returning `:lt`, `:eq`, or `:gt`."
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{amount: a, currency: c}, %__MODULE__{amount: b, currency: c}) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  def compare(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError, "cannot compare #{c1} and #{c2}"
  end

  @doc "True when the amount is strictly negative."
  @spec negative?(t()) :: boolean()
  def negative?(%__MODULE__{amount: a}), do: a < 0

  @doc "True when the amount is strictly positive."
  @spec positive?(t()) :: boolean()
  def positive?(%__MODULE__{amount: a}), do: a > 0

  @doc "True when the amount is zero."
  @spec zero?(t()) :: boolean()
  def zero?(%__MODULE__{amount: a}), do: a == 0

  @doc "Serialises to a JSON-friendly map."
  @spec to_map(t()) :: %{amount: integer(), currency: String.t()}
  def to_map(%__MODULE__{amount: a, currency: c}), do: %{amount: a, currency: c}

  @doc "Builds money from a map with `amount` and `currency` keys."
  @spec from_map(%{amount: integer(), currency: String.t()}) :: t()
  def from_map(%{"amount" => amount, "currency" => currency}), do: new(amount, currency)
  def from_map(%{amount: amount, currency: currency}), do: new(amount, currency)

  @doc "Formats as e.g. `\"12.34 CAD\"` (no locale symbols)."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{amount: a, currency: c}) do
    sign = if a < 0, do: "-", else: ""
    a = abs(a)
    "#{sign}#{div(a, 100)}.#{String.pad_leading("#{rem(a, 100)}", 2, "0")} #{c}"
  end

  defp round_half_up(value, divisor) do
    # Round half away from zero.
    quotient = div(value, divisor)
    remainder = rem(value, divisor)

    cond do
      remainder * 2 >= divisor -> quotient + 1
      remainder * 2 <= -divisor -> quotient - 1
      true -> quotient
    end
  end
end
