defmodule SportsCoachBookingsWeb.Webhooks.StripeController do
  @moduledoc """
  Stripe Connect webhooks. The signature is verified over the raw request body
  (via `SportsCoachBookingsWeb.Plugs.CachedBodyReader`), the event is recorded
  deduped on `(provider, event_id)`, and processing is deferred to an Oban job.
  """

  use SportsCoachBookingsWeb, :controller

  alias SportsCoachBookings.Payments

  @doc "POST /webhooks/stripe"
  def create(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    headers = Map.new(conn.req_headers)

    case Payments.ingest_webhook(:stripe, raw_body, headers) do
      {:ok, :received} ->
        json(conn, %{received: true})

      {:ok, :duplicate} ->
        json(conn, %{received: true, duplicate: true})

      {:error, :invalid_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: %{
            code: "invalid_signature",
            message: "Invalid webhook signature",
            details: %{}
          }
        })
    end
  end
end
