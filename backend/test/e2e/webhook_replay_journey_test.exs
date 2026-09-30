defmodule SportsCoachBookings.E2E.WebhookReplayJourneyTest do
  @moduledoc """
  WP-18 end-to-end: invariant 6 — replaying a provider webhook never
  double-charges, double-fulfils, or double-grants. Covers both the Stripe
  (payments) and Resend (notifications) webhooks through their real endpoints.
  """
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query
  import SportsCoachBookings.E2EHelpers

  alias Phoenix.ConnTest
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.DeliveryRef
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Notifications.ResendEventHandler
  alias SportsCoachBookings.Notifications.WebhookEvent, as: NotificationsWebhookEvent
  alias SportsCoachBookings.Payments.WebhookEvent, as: PaymentsWebhookEvent
  alias SportsCoachBookings.Repo

  @customer_email "dana@replay.test"

  setup do
    %{tenant: tenant, slug: slug, owner: owner} =
      onboard_tenant(build_conn(), %{
        name: "Replay Co",
        slug: "replay-#{System.unique_integer([:positive])}",
        email: "owner@replay.test"
      })

    assert %{"url" => _} =
             owner
             |> post("/api/staff/payments/connect/onboarding")
             |> json_response(200)

    owner |> get("/api/staff/payments/connect") |> json_response(200)

    package =
      owner
      |> json_post("/api/staff/catalog/packages", %{
        "name" => "Replay Pack",
        "credit_quantity" => 4,
        "price" => 4_000
      })
      |> json_response(201)

    reg_conn = register_customer(build_conn(), slug, @customer_email)
    assert %{"household" => %{"id" => household_id}} = json_response(reg_conn, 201)

    DataCase.put_tenant(tenant)
    user = Customers.get_customer_user_by_email(@customer_email)
    token = Customers.create_confirm_token(user)
    build_conn() |> host(slug) |> json_post("/api/portal/confirmation", %{token: token})

    customer = ConnTest.recycle(reg_conn)

    customer
    |> json_post("/api/portal/cart/lines", %{
      "line" => %{"type" => "package", "ref_id" => package["id"], "quantity" => 1}
    })
    |> json_response(201)

    checkout = customer |> post("/api/portal/checkout") |> json_response(201)

    %{
      tenant: tenant,
      slug: slug,
      customer: customer,
      household_id: household_id,
      order_id: checkout["order"]["id"]
    }
  end

  test "a replayed Stripe checkout webhook grants exactly once", ctx do
    %{tenant: tenant, household_id: household_id, order_id: order_id} = ctx

    # Same event id three times: recorded once, processed once.
    for _ <- 1..3 do
      assert json_response(complete_checkout(build_conn(), tenant, order_id, 4_000), 200)[
               "received"
             ] == true
    end

    assert Repo.aggregate(PaymentsWebhookEvent, :count) == 1

    drain_outbox()
    DataCase.put_tenant(tenant)

    assert Commerce.get_order!(order_id).status == :paid
    assert length(Credits.list_lots(household_id)) == 1
    assert Credits.list_ledger(household_id) |> Enum.sum_by(& &1.delta) == 4
    assert {:ok, 4} = Credits.reconcile(household_id)
    assert delivery_count(@customer_email, "order_receipt") == 1
    assert delivery_count(@customer_email, "credits_granted") == 1
  end

  test "a replayed Resend delivery webhook is applied once", ctx do
    %{tenant: tenant, order_id: order_id} = ctx

    assert json_response(complete_checkout(build_conn(), tenant, order_id, 4_000), 200)
    drain_outbox()
    DataCase.put_tenant(tenant)

    # Bind the queued receipt to a provider message id (as the delivery worker
    # would after a real send).
    receipt =
      Repo.one!(
        from d in Delivery,
          join: m in Message,
          on: m.id == d.message_id,
          where: d.email == ^@customer_email and m.template_key == "order_receipt"
      )

    receipt =
      receipt
      |> Ecto.Changeset.change(provider_ref: "email_replay_1")
      |> Repo.update!()

    %DeliveryRef{}
    |> DeliveryRef.changeset(%{
      provider: "resend",
      provider_ref: "email_replay_1",
      tenant_id: tenant.id,
      delivery_id: receipt.id
    })
    |> Repo.insert!()

    payload = %{
      "type" => "email.delivered",
      "data" => %{"email_id" => "email_replay_1", "to" => @customer_email}
    }

    assert json_response(resend_webhook(build_conn(), "evt_replay", payload), 200)["received"] ==
             true

    assert Repo.aggregate(NotificationsWebhookEvent, :count) == 1

    # Exactly one handler job was enqueued; running it marks the delivery once.
    assert [job] = resend_handler_jobs()
    assert :ok = ResendEventHandler.perform(job)
    assert Repo.get!(Delivery, receipt.id).status == :delivered

    # Once processed, a replay with the same svix-id is a true no-op.
    assert json_response(resend_webhook(build_conn(), "evt_replay", payload), 200)["duplicate"] ==
             true

    assert Repo.aggregate(NotificationsWebhookEvent, :count) == 1
    assert length(resend_handler_jobs()) == 1
  end

  defp resend_handler_jobs do
    Repo.all(
      from j in Oban.Job,
        where: j.worker == "SportsCoachBookings.Notifications.ResendEventHandler",
        order_by: [asc: j.id]
    )
  end
end
