defmodule SportsCoachBookings.Notifications.ResendEventHandler do
  @moduledoc """
  Applies a Resend delivery event to a `deliveries` row. Runs with tenant
  context restored by `SportsCoachBookings.Core.TenantWorker`.

  A hard bounce or a complaint also suppresses the recipient (except password
  reset, which is exempt at send time).
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :notifications, max_attempts: 5

  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.Suppressions
  alias SportsCoachBookings.Notifications.WebhookEvent
  alias SportsCoachBookings.Repo

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: args}) do
    case Repo.with_tenant_tx(fn -> apply_event(args) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_event(args) do
    result =
      case Repo.get(Delivery, args["delivery_id"]) do
        nil -> {:discard, :delivery_not_found}
        delivery -> handle(args["event_type"], delivery, args)
      end

    mark_processed(args["webhook_event_id"])
    result
  end

  defp handle("email.delivered", delivery, _args) do
    {:ok, _} = update_delivery(delivery, %{status: :delivered, delivered_at: now()})
    :ok
  end

  defp handle("email.bounced", delivery, args) do
    attrs = %{status: :bounced, bounced_at: now(), error: error_for(args)}
    {:ok, _} = update_delivery(delivery, attrs)

    if hard_bounce?(args["bounce_type"]) do
      Suppressions.suppress(delivery.tenant_id, delivery.email, :bounce)
    end

    :ok
  end

  defp handle("email.complained", delivery, _args) do
    {:ok, _} = update_delivery(delivery, %{status: :complained, error: "complaint"})
    Suppressions.suppress(delivery.tenant_id, delivery.email, :complaint)
    :ok
  end

  defp handle(_type, _delivery, _args), do: :ok

  defp update_delivery(delivery, attrs) do
    delivery
    |> Delivery.changeset(attrs)
    |> Repo.update()
  end

  defp hard_bounce?(nil), do: true
  defp hard_bounce?(type) when is_binary(type), do: String.downcase(type) in ["permanent", "hard"]

  defp error_for(args) do
    [args["bounce_type"], args["reason"]]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "bounced"
      parts -> Enum.join(parts, ": ")
    end
  end

  defp mark_processed(nil), do: :ok

  defp mark_processed(event_id) do
    case Repo.get(WebhookEvent, event_id) do
      nil ->
        :ok

      event ->
        event
        |> WebhookEvent.changeset(%{processed_at: now()})
        |> Repo.update()
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
