defmodule SportsCoachBookings.Payments.WebhookFlowTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Payments
  alias SportsCoachBookings.Payments.Payment
  alias SportsCoachBookings.Payments.Refund
  alias SportsCoachBookings.Payments.WebhookWorker
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant, slug: "hooks-co")
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp webhook(event_id, type, data) do
    Jason.encode!(%{"id" => event_id, "type" => type, "data" => data})
  end

  defp ingest(body) do
    Payments.ingest_webhook(:stripe, body, %{})
  end

  defp payment_jobs do
    Repo.all(
      from j in Oban.Job,
        where: j.queue == "payments" and j.worker == "SportsCoachBookings.Payments.WebhookWorker"
    )
  end

  defp run_jobs do
    Enum.each(payment_jobs(), fn job -> assert :ok = WebhookWorker.perform_with_tenant(job) end)
  end

  defp event_count(name) do
    Repo.all(
      from j in Oban.Job, where: j.queue == "events" and j.args["name"] == ^name, select: j.id
    )
    |> length()
  end

  defp pending_payment do
    insert(:provider_account, charges_enabled: true)

    order = %{
      "id" => Ecto.UUID.generate(),
      "number" => "A-0001",
      "currency" => "CAD",
      "line_items" => [%{"name" => "Pack", "unit_amount" => 5_000, "quantity" => 1}]
    }

    {:ok, _url} = Payments.create_checkout(order)
    {order, Repo.get_by(Payment, order_id: order["id"])}
  end

  test "checkout.session.completed publishes payment.succeeded exactly once across replays", %{
    tenant: tenant
  } do
    {_order, payment} = pending_payment()

    body =
      webhook("evt_completed", "checkout.session.completed", %{
        "tenant_id" => tenant.id,
        "checkout_ref" => payment.checkout_ref,
        "payment_ref" => "pi_1",
        "amount" => 5_000,
        "currency" => "CAD"
      })

    assert {:ok, :received} = ingest(body)
    assert {:ok, :received} = ingest(body)
    assert {:ok, :received} = ingest(body)

    # While the event is still unprocessed, replays may enqueue more jobs
    # (at-least-once). Processing is idempotent, so the event fires once.
    assert payment_jobs() != []

    run_jobs()

    assert Repo.get!(Payment, payment.id).status == :succeeded
    assert Repo.get!(Payment, payment.id).payment_ref == "pi_1"
    assert event_count("payment.succeeded") == 1

    # Once processed, a replay is a true no-op and enqueues nothing new.
    enqueued = length(payment_jobs())
    assert {:ok, :duplicate} = ingest(body)
    assert length(payment_jobs()) == enqueued

    # Reprocessing the same job (or a concurrent worker) must not re-publish.
    run_jobs()
    assert event_count("payment.succeeded") == 1
  end

  test "checkout.session.expired marks a pending payment expired", %{tenant: tenant} do
    {_order, payment} = pending_payment()

    body =
      webhook("evt_expired", "checkout.session.expired", %{
        "tenant_id" => tenant.id,
        "checkout_ref" => payment.checkout_ref
      })

    assert {:ok, :received} = ingest(body)
    run_jobs()

    assert Repo.get!(Payment, payment.id).status == :expired
    assert event_count("payment.succeeded") == 0
  end

  test "payment_intent.payment_failed publishes payment.failed once", %{tenant: tenant} do
    insert(:provider_account, charges_enabled: true)
    payment = insert(:payment, status: :pending, checkout_ref: "cs_fail", amount: 2_500)

    body =
      webhook("evt_failed", "payment_intent.payment_failed", %{
        "tenant_id" => tenant.id,
        "payment_ref" => payment.payment_ref || "pi_fail",
        "amount" => 2_500,
        "currency" => "CAD"
      })

    payment = Repo.update!(Ecto.Changeset.change(payment, payment_ref: "pi_fail"))

    assert {:ok, :received} = ingest(body)
    run_jobs()

    assert Repo.get!(Payment, payment.id).status == :failed
    assert event_count("payment.failed") == 1
  end

  test "charge.refunded reconciles partial and full refunds once", %{tenant: tenant} do
    payment =
      insert(:payment,
        status: :succeeded,
        payment_ref: "pi_refund",
        checkout_ref: "cs_refund",
        amount: 5_000
      )

    partial =
      webhook("evt_refund_1", "charge.refunded", %{
        "tenant_id" => tenant.id,
        "payment_ref" => payment.payment_ref,
        "refund_ref" => "re_1",
        "refund_amount" => 2_000,
        "currency" => "CAD"
      })

    assert {:ok, :received} = ingest(partial)
    run_jobs()

    assert [refund] = Payments.list_refunds(payment.id)
    assert refund.refund_ref == "re_1"
    assert refund.amount == 2_000
    assert event_count("payment.refunded") == 1

    full =
      webhook("evt_refund_2", "charge.refunded", %{
        "tenant_id" => tenant.id,
        "payment_ref" => payment.payment_ref,
        "refund_ref" => "re_2",
        "refund_amount" => 3_000,
        "currency" => "CAD"
      })

    assert {:ok, :received} = ingest(full)
    run_jobs()

    assert length(Payments.list_refunds(payment.id)) == 2
    assert event_count("payment.refunded") == 2

    # A new webhook event (different event id) carrying the same refund ref must
    # not create a second refund row nor re-publish.
    replay =
      webhook("evt_refund_1b", "charge.refunded", %{
        "tenant_id" => tenant.id,
        "payment_ref" => payment.payment_ref,
        "refund_ref" => "re_1",
        "refund_amount" => 2_000,
        "currency" => "CAD"
      })

    assert {:ok, :received} = ingest(replay)
    run_jobs()

    assert length(Payments.list_refunds(payment.id)) == 2
    assert event_count("payment.refunded") == 2
    assert Repo.aggregate(Refund, :count) == 2
  end

  test "account.updated syncs the connected account readiness", %{tenant: tenant} do
    account = insert(:provider_account, charges_enabled: false, status: "pending")

    body =
      webhook("evt_account", "account.updated", %{
        "tenant_id" => tenant.id,
        "account_ref" => account.account_ref,
        "charges_enabled" => true,
        "payouts_enabled" => true,
        "requirements" => %{}
      })

    assert {:ok, :received} = ingest(body)
    run_jobs()

    updated = Repo.get!(SportsCoachBookings.Payments.ProviderAccount, account.id)
    assert updated.charges_enabled
    assert updated.payouts_enabled
    assert updated.status == "enabled"
  end

  test "unhandled event types are recorded and never enqueued" do
    body = webhook("evt_unknown", "customer.created", %{})
    assert {:ok, :received} = ingest(body)
    assert payment_jobs() == []
    assert Repo.get_by!(SportsCoachBookings.Payments.WebhookEvent, event_id: "evt_unknown")
  end
end
