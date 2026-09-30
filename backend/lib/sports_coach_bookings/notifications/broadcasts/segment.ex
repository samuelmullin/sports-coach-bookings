defmodule SportsCoachBookings.Notifications.Broadcasts.Segment do
  @moduledoc """
  The embedded, AND-composable recipient segment definition for a broadcast.

  A segment is stored as a JSON-safe map:

      %{
        "match" => "all" | "any",
        "conditions" => [%{"type" => "bookings", ...}, ...]
      }

  Every condition is evaluated to a set of household ids; `"all"` intersects the
  sets (AND) and `"any"` unions them (OR). An empty condition list with
  `"match" => "all"` means *all households*.

  Supported condition types:

    * `"bookings"` — households with a booking in the given
      `session_ids`/`offering_ids`/`venue_id`/`from`/`to`, with an optional
      `"status"` (default `"confirmed"`).
    * `"player_age"` — households with an active player aged `min`..`max`.
    * `"credits"` — households with a credit balance `>= min_balance` (default
      `1`) and/or a lot with remaining credits expiring before
      `expiring_before`.
    * `"package"` — households that purchased `package_id` (paid orders).

  `normalize/1` also accepts a bare condition map (one with a `"type"` key) and
  the legacy `%{"all" => true}` shortcut.
  """

  @types ~w(bookings player_age credits package)

  @type condition :: map()
  @type t :: %{required(String.t()) => term()}

  @doc "The supported condition type names."
  @spec types() :: [String.t()]
  def types, do: @types

  @doc """
  Normalises any accepted segment shape into the canonical form.

  Does not validate; use `validate/1` when the input is untrusted.
  """
  @spec normalize(term()) :: t()
  def normalize(nil), do: empty()
  def normalize(:all), do: empty()
  def normalize(%{"all" => true}), do: empty()
  def normalize(%{all: true}), do: empty()

  def normalize(%{} = raw) do
    match = stringify(fetch(raw, :match) || "all")
    conditions = fetch(raw, :conditions)

    cond do
      is_list(conditions) ->
        %{"match" => match, "conditions" => Enum.map(conditions, &normalize_condition/1)}

      fetch(raw, :type) != nil ->
        %{"match" => "all", "conditions" => [normalize_condition(raw)]}

      true ->
        empty()
    end
  end

  def normalize(_other), do: empty()

  @doc "An empty segment (all households under `match: all`)."
  @spec empty() :: t()
  def empty, do: %{"match" => "all", "conditions" => []}

  @doc "Whether the segment has no conditions."
  @spec empty?(t()) :: boolean()
  def empty?(%{"conditions" => []}), do: true
  def empty?(%{conditions: []}), do: true
  def empty?(_segment), do: false

  @doc """
  Validates and normalises a segment.

  Returns `{:ok, canonical}` or `{:error, {:invalid_segment, reason}}`.
  """
  @spec validate(term()) :: {:ok, t()} | {:error, {:invalid_segment, term()}}
  def validate(raw) do
    segment = normalize(raw)

    with :ok <- validate_match(segment),
         {:ok, conditions} <- validate_conditions(segment["conditions"]) do
      {:ok, %{segment | "conditions" => conditions}}
    end
  end

  @doc """
  Whether an operational broadcast's segment is booking-based.

  Operational mail may not be sent to "all households"; at least one
  `"bookings"` condition is required.
  """
  @spec operational_booking_based?(t()) :: boolean()
  def operational_booking_based?(segment) do
    segment
    |> normalize()
    |> Map.get("conditions", [])
    |> Enum.any?(&(fetch(&1, :type) == "bookings"))
  end

  ## Internal

  defp normalize_condition(%{} = raw) do
    raw
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_condition(other), do: other

  defp validate_match(%{"match" => match}) when match in ["all", "any"], do: :ok
  defp validate_match(_segment), do: {:error, {:invalid_segment, "match must be all or any"}}

  defp validate_conditions(conditions) when is_list(conditions) do
    Enum.reduce_while(conditions, {:ok, []}, fn condition, {:ok, acc} ->
      case validate_condition(condition) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp validate_conditions(_conditions),
    do: {:error, {:invalid_segment, "conditions must be a list"}}

  defp validate_condition(%{} = condition) do
    type = fetch(condition, :type)

    if type in @types do
      validate_condition_type(type, condition)
    else
      {:error, {:invalid_segment, "unknown condition type: #{inspect(type)}"}}
    end
  end

  defp validate_condition(other),
    do: {:error, {:invalid_segment, "condition must be an object, got: #{inspect(other)}"}}

  defp validate_condition_type("bookings", condition), do: {:ok, condition}

  defp validate_condition_type("player_age", condition) do
    with :ok <- require_number(condition, "min", allow_nil: true),
         :ok <- require_number(condition, "max", allow_nil: true) do
      if fetch(condition, :min) == nil and fetch(condition, :max) == nil do
        {:error, {:invalid_segment, "player_age requires min or max"}}
      else
        {:ok, condition}
      end
    end
  end

  defp validate_condition_type("credits", condition) do
    with :ok <- require_number(condition, "min_balance", allow_nil: true) do
      {:ok, condition}
    end
  end

  defp validate_condition_type("package", condition) do
    if is_binary(fetch(condition, :package_id)) and fetch(condition, :package_id) != "" do
      {:ok, condition}
    else
      {:error, {:invalid_segment, "package requires package_id"}}
    end
  end

  defp require_number(condition, key, opts) do
    case fetch(condition, key) do
      nil ->
        if Keyword.get(opts, :allow_nil, false),
          do: :ok,
          else: {:error, {:invalid_segment, "#{key} is required"}}

      value when is_integer(value) ->
        :ok

      value when is_float(value) ->
        :ok

      value when is_binary(value) ->
        case Integer.parse(value) do
          {_int, ""} -> :ok
          _ -> {:error, {:invalid_segment, "#{key} must be a number"}}
        end

      _ ->
        {:error, {:invalid_segment, "#{key} must be a number"}}
    end
  end

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, to_string(key)) || Map.get(map, key)

  defp fetch(_map, _key), do: nil

  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: value
end
