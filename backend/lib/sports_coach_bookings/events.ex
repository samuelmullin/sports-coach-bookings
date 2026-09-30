defmodule SportsCoachBookings.Events do
  @moduledoc """
  Transactional domain-event publishing.

  `publish/2` must be called inside the same transaction as the state change it
  announces. The event is written as an Oban job on the `:events` queue in that
  same transaction (a transactional outbox), so it is delivered if and only if
  the transaction commits. The event worker then dispatches to every subscriber
  registered in `config :sports_coach_bookings, :event_subscribers`.

  Payloads carry identifiers plus `tenant_id` — never structs — and must be
  JSON-serialisable. Subscribers must be idempotent: an event may be delivered
  more than once.
  """

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events.EventWorker

  @doc """
  Publishes `name` with `payload` by inserting an outbox job in the current
  transaction.
  """
  @spec publish(atom() | String.t(), map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def publish(name, payload \\ %{}) when is_map(payload) do
    args = %{
      "tenant_id" => TenantContext.get_tenant_id(),
      "name" => to_string(name),
      "payload" => stringify(payload)
    }

    args
    |> EventWorker.new()
    |> Oban.insert()
  end

  @doc """
  The subscriber modules configured for `name`.
  """
  @spec subscribers(String.t()) :: [module()]
  def subscribers(name) when is_binary(name) do
    :sports_coach_bookings
    |> Application.get_env(:event_subscribers, %{})
    |> Map.get(name, [])
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp stringify_value(%Date{} = value), do: Date.to_iso8601(value)
  defp stringify_value(%Time{} = value), do: Time.to_iso8601(value)
  defp stringify_value(%{__struct__: _} = value), do: Map.get(value, :id)
  defp stringify_value(list) when is_list(list), do: Enum.map(list, &stringify_value/1)
  defp stringify_value(map) when is_map(map), do: stringify(map)
  defp stringify_value(value), do: value
end
