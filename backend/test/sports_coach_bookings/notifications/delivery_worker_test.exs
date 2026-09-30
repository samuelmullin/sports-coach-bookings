defmodule SportsCoachBookings.Notifications.DeliveryWorkerTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.DeliveryWorker

  defmodule FailingDeliverer do
    @behaviour SportsCoachBookings.Notifications.Deliverer

    @impl true
    def deliver(_email), do: {:error, :smtp_down}
  end

  @assigns %{name: "Alex", action_url: "https://example.com"}

  defp enqueue_delivery(tenant) do
    put_tenant(tenant)

    {:ok, %{deliveries: [delivery]}} =
      Notifications.deliver(:sample, [%{type: :email, email: "worker@example.com"}], @assigns)

    delivery
  end

  defp job(delivery, tenant, attempt, max_attempts) do
    %Oban.Job{
      args: %{"delivery_id" => delivery.id, "tenant_id" => tenant.id, "attachments" => []},
      attempt: attempt,
      max_attempts: max_attempts
    }
  end

  test "a successful send marks the delivery sent" do
    tenant = insert(:tenant)
    delivery = enqueue_delivery(tenant)

    assert :ok = DeliveryWorker.perform_with_tenant(job(delivery, tenant, 1, 5))

    updated = Repo.get!(Delivery, delivery.id)
    assert updated.status == :sent
    assert updated.sent_at
    assert is_nil(updated.error)
  end

  test "a failure retries with backoff and is marked failed on the last attempt" do
    tenant = insert(:tenant)
    delivery = enqueue_delivery(tenant)

    previous_deliverer = Application.get_env(:sports_coach_bookings, :notifications_deliverer)
    Application.put_env(:sports_coach_bookings, :notifications_deliverer, FailingDeliverer)

    on_exit(fn ->
      Application.put_env(:sports_coach_bookings, :notifications_deliverer, previous_deliverer)
    end)

    assert {:error, :smtp_down} = DeliveryWorker.perform_with_tenant(job(delivery, tenant, 1, 5))
    retried = Repo.get!(Delivery, delivery.id)
    assert retried.status == :queued
    assert retried.error =~ "smtp_down"

    assert {:discard, :smtp_down} =
             DeliveryWorker.perform_with_tenant(job(delivery, tenant, 5, 5))

    assert Repo.get!(Delivery, delivery.id).status == :failed
  end

  test "backoff grows with the attempt number" do
    assert DeliveryWorker.backoff(%Oban.Job{attempt: 1}) == 16
    assert DeliveryWorker.backoff(%Oban.Job{attempt: 3}) == 96
    assert DeliveryWorker.backoff(%Oban.Job{attempt: 100}) == 3600
  end

  test "an unknown template discards the job" do
    tenant = insert(:tenant)
    delivery = enqueue_delivery(tenant)

    # Point the message at a template that is not registered.
    Repo.get!(SportsCoachBookings.Notifications.Message, delivery.message_id)
    |> Ecto.Changeset.change(template_key: "gone")
    |> Repo.update!()

    assert {:discard, {:unknown_template, "gone"}} =
             DeliveryWorker.perform_with_tenant(job(delivery, tenant, 1, 5))
  end

  test "a delivery without tenant_id fails the TenantWorker contract" do
    assert {:error, {:missing_tenant_id, %{}}} =
             DeliveryWorker.perform(%Oban.Job{args: %{}, attempt: 1, max_attempts: 5})
  end
end
