defmodule SportsCoachBookingsWeb.StripeWebhookTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Payments.Providers.Stripe
  alias SportsCoachBookings.Payments.WebhookEvent
  alias SportsCoachBookings.Repo

  defp post_webhook(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/webhooks/stripe", body)
  end

  test "records a valid webhook and ignores replays", %{conn: conn} do
    body =
      Jason.encode!(%{
        "id" => "evt_1",
        "type" => "customer.created",
        "data" => %{}
      })

    assert json_response(post_webhook(conn, body), 200)["received"] == true

    event = Repo.get_by(WebhookEvent, provider: "stripe", event_id: "evt_1")
    assert event
    assert Repo.aggregate(WebhookEvent, :count) == 1

    # Once processed, a replay is a true no-op.
    event
    |> WebhookEvent.changeset(%{processed_at: DateTime.utc_now()})
    |> Repo.update!()

    assert json_response(post_webhook(conn, body), 200)["duplicate"] == true
    assert Repo.aggregate(WebhookEvent, :count) == 1
  end

  test "rejects an invalid signature when the Stripe adapter is configured", %{conn: conn} do
    previous = Application.get_env(:sports_coach_bookings, :payments_provider)
    Application.put_env(:sports_coach_bookings, :payments_provider, Stripe)
    on_exit(fn -> Application.put_env(:sports_coach_bookings, :payments_provider, previous) end)

    response =
      post_webhook(conn, Jason.encode!(%{"id" => "evt_bad", "type" => "x", "data" => %{}}))

    assert json_response(response, 401)["error"]["code"] == "invalid_signature"
  end
end
