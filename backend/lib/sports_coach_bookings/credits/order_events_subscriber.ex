defmodule SportsCoachBookings.Credits.OrderEventsSubscriber do
  @moduledoc """
  Reacts to the Commerce order lifecycle for credit-bearing package lines.
  Owned by WP-12.

  Registered in `config :sports_coach_bookings, :event_subscribers` for
  `order.paid` and `order.refunded`.

    * `order.paid` — grants the purchased package credits to the household.
      Idempotent on the order line, so replaying the event cannot double-grant.
    * `order.refunded` — revokes the still-unused credits on the refunded
      package lines. The used portion is not clawed back.

  Delivery is at-least-once. The expected payload shape is documented in
  `docs/rfcs/20260928-credits-commerce-event-contract.md`.
  """

  @behaviour SportsCoachBookings.Events.Subscriber

  alias SportsCoachBookings.Credits

  @impl true
  def handle_event("order.paid", payload) do
    with {:ok, household_id} <- household_id(payload) do
      payload
      |> lines()
      |> Enum.reduce_while(:ok, &grant_line(household_id, &1, &2))
    end
  end

  def handle_event("order.refunded", payload) do
    payload
    |> lines()
    |> Enum.reduce_while(:ok, &refund_line/2)
  end

  def handle_event(_name, _payload), do: :ok

  defp grant_line(household_id, line, :ok) do
    case package_id(line) do
      nil -> {:cont, :ok}
      package_id -> do_grant_line(household_id, package_id, line)
    end
  end

  defp do_grant_line(household_id, package_id, line) do
    case Credits.grant(household_id, package_id, order_line_id(line), quantity: quantity(line)) do
      {:ok, _lot} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp refund_line(line, :ok) do
    case order_line_id(line) do
      nil -> {:cont, :ok}
      order_line_id -> do_refund_line(order_line_id)
    end
  end

  defp do_refund_line(order_line_id) do
    case Credits.revoke_unused(nil, order_line_id) do
      {:ok, _result} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp household_id(payload) do
    case field(payload, "household_id") do
      nil -> {:error, :missing_household_id}
      household_id -> {:ok, household_id}
    end
  end

  defp lines(payload), do: field(payload, "lines") || []

  defp package_id(line), do: field(line, "package_id")
  defp order_line_id(line), do: field(line, "order_line_id") || field(line, "id")
  defp quantity(line), do: field(line, "quantity") || 1

  defp field(container, key) when is_map(container) do
    Map.get(container, key) || Map.get(container, safe_atom(key))
  end

  defp field(_container, _key), do: nil

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :__missing__
  end
end
