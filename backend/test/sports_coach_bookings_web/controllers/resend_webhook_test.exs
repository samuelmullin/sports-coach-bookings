defmodule SportsCoachBookingsWeb.ResendWebhookTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.ResendEventHandler
  alias SportsCoachBookings.Notifications.Suppressions
  alias SportsCoachBookings.Notifications.WebhookEvent
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant, slug: "acme")
    DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  defp signed_request(conn, payload, event_id) do
    timestamp = Integer.to_string(System.system_time(:second))
    secret = Application.get_env(:sports_coach_bookings, :resend_webhook_secret)
    raw_key = secret |> String.replace_prefix("whsec_", "") |> Base.decode64!()
    signature = :crypto.mac(:hmac, :sha256, raw_key, "#{event_id}.#{timestamp}.#{payload}")

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("svix-id", event_id)
    |> put_req_header("svix-timestamp", timestamp)
    |> put_req_header("svix-signature", "v1," <> Base.encode64(signature))
    |> post("/webhooks/resend", payload)
  end

  defp notifications_jobs do
    Repo.all(Oban.Job) |> Enum.filter(&(&1.queue == "notifications"))
  end

  defp handler_jobs do
    notifications_jobs()
    |> Enum.filter(&(&1.worker == "SportsCoachBookings.Notifications.ResendEventHandler"))
  end

  test "rejects a bad signature", %{conn: conn} do
    payload = Jason.encode!(%{"type" => "email.delivered", "data" => %{}})

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("svix-id", "evt_bad")
      |> put_req_header("svix-timestamp", Integer.to_string(System.system_time(:second)))
      |> put_req_header("svix-signature", "v1,bogus")
      |> post("/webhooks/resend", payload)

    assert json_response(response, 401)["error"]["code"] == "invalid_signature"
  end

  test "records, enqueues, applies, and ignores replays", %{conn: conn, tenant: tenant} do
    {:ok, %{deliveries: [delivery]}} =
      Notifications.deliver(
        :sample,
        [%{type: :email, email: "hook@example.com"}],
        %{name: "Alex", action_url: "https://example.com"}
      )

    delivery =
      delivery
      |> Ecto.Changeset.change(provider_ref: "email_123")
      |> Repo.update!()

    insert(:delivery_ref,
      provider_ref: "email_123",
      tenant_id: tenant.id,
      delivery_id: delivery.id
    )

    payload =
      Jason.encode!(%{
        "type" => "email.delivered",
        "data" => %{"email_id" => "email_123", "to" => "hook@example.com"}
      })

    assert json_response(signed_request(conn, payload, "evt_1"), 200)["received"] == true

    assert [job] = handler_jobs()
    assert job.args["event_type"] == "email.delivered"
    assert job.args["delivery_id"] == delivery.id
    assert job.args["tenant_id"] == tenant.id

    assert :ok = ResendEventHandler.perform_with_tenant(job)
    assert Repo.get!(Delivery, delivery.id).status == :delivered
    assert Repo.get_by(WebhookEvent, event_id: "evt_1").processed_at

    # Replay: same svix-id is a no-op and enqueues nothing new.
    assert json_response(signed_request(conn, payload, "evt_1"), 200)["duplicate"] == true
    assert Repo.aggregate(WebhookEvent, :count) == 1
    assert length(handler_jobs()) == 1
  end

  test "a bounce suppresses a hard-bounced address", %{conn: conn, tenant: tenant} do
    {:ok, %{deliveries: [delivery]}} =
      Notifications.deliver(
        :sample,
        [%{type: :email, email: "bounce@example.com"}],
        %{name: "Alex", action_url: "https://example.com"}
      )

    delivery =
      delivery
      |> Ecto.Changeset.change(provider_ref: "email_bounce")
      |> Repo.update!()

    insert(:delivery_ref,
      provider_ref: "email_bounce",
      tenant_id: tenant.id,
      delivery_id: delivery.id
    )

    payload =
      Jason.encode!(%{
        "type" => "email.bounced",
        "data" => %{"email_id" => "email_bounce", "bounce" => %{"type" => "Permanent"}}
      })

    assert json_response(signed_request(conn, payload, "evt_bounce"), 200)["received"] == true
    [job] = handler_jobs()

    assert :ok = ResendEventHandler.perform_with_tenant(job)
    assert Repo.get!(Delivery, delivery.id).status == :bounced

    assert Suppressions.suppressed?(tenant.id, "bounce@example.com")
  end
end
