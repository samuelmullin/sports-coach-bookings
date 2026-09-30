defmodule SportsCoachBookingsWeb.Webhooks.ResendController do
  @moduledoc """
  Resend delivery webhooks. Verifies the Svix signature over the raw body,
  records the event (replays are no-ops), and enqueues
  `SportsCoachBookings.Notifications.ResendEventHandler` with the tenant resolved
  from the provider message id.
  """

  use SportsCoachBookingsWeb, :controller

  alias SportsCoachBookings.Notifications.DeliveryRef
  alias SportsCoachBookings.Notifications.ResendEventHandler
  alias SportsCoachBookings.Notifications.Signature
  alias SportsCoachBookings.Notifications.WebhookEvent
  alias SportsCoachBookings.Repo

  @provider "resend"

  @doc "POST /webhooks/resend"
  def create(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    headers = Map.new(conn.req_headers)

    case Signature.verify(raw_body, headers, secret(), tolerance: tolerance()) do
      :ok ->
        handle(conn, raw_body, headers)

      {:error, reason} ->
        error(conn, :unauthorized, "invalid_signature", "Invalid webhook signature", %{
          reason: to_string(reason)
        })
    end
  end

  defp handle(conn, raw_body, headers) do
    case Jason.decode(raw_body) do
      {:ok, payload} ->
        event_id = headers["svix-id"] || payload["id"] || Ecto.UUID.generate()
        type = payload["type"] || "unknown"

        case record_event(event_id, type, payload) do
          {:ok, :duplicate} ->
            json(conn, %{received: true, duplicate: true})

          {:ok, event} ->
            enqueue(event, payload)
            json(conn, %{received: true})

          {:error, _reason} ->
            error(conn, :unprocessable_entity, "invalid_payload", "Could not record webhook", %{})
        end

      _ ->
        error(conn, :bad_request, "invalid_json", "Invalid JSON body", %{})
    end
  end

  defp record_event(event_id, type, payload) do
    case Repo.get_by(WebhookEvent, provider: @provider, event_id: event_id) do
      %WebhookEvent{processed_at: nil} = event ->
        # Seen before but never processed: re-enqueue rather than drop it.
        {:ok, event}

      %WebhookEvent{} ->
        {:ok, :duplicate}

      nil ->
        %WebhookEvent{}
        |> WebhookEvent.changeset(%{
          provider: @provider,
          event_id: event_id,
          type: type,
          payload: payload
        })
        |> Repo.insert()
    end
  end

  defp enqueue(event, payload) do
    case delivery_ref(payload) do
      nil ->
        :ok

      %DeliveryRef{} = ref ->
        args = %{
          "tenant_id" => ref.tenant_id,
          "delivery_id" => ref.delivery_id,
          "event_type" => payload["type"],
          "webhook_event_id" => event.id,
          "bounce_type" => get_in(payload, ["data", "bounce", "type"]),
          "reason" => get_in(payload, ["data", "bounce", "diagnostic"])
        }

        args
        |> ResendEventHandler.new()
        |> Oban.insert()

        :ok
    end
  end

  defp delivery_ref(payload) do
    case get_in(payload, ["data", "email_id"]) || get_in(payload, ["data", "id"]) do
      nil -> nil
      provider_ref -> Repo.get_by(DeliveryRef, provider: @provider, provider_ref: provider_ref)
    end
  end

  defp secret, do: Application.get_env(:sports_coach_bookings, :resend_webhook_secret)

  defp tolerance,
    do: Application.get_env(:sports_coach_bookings, :resend_webhook_tolerance, 300)

  defp error(conn, status, code, message, details) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, details: details}})
  end
end
