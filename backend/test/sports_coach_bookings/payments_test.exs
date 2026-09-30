defmodule SportsCoachBookings.PaymentsTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Payments
  alias SportsCoachBookings.Payments.Payment
  alias SportsCoachBookings.Payments.ProviderAccount
  alias SportsCoachBookings.Payments.Refund
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant, slug: "pay-co")
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp order(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "number" => "A-0001",
        "currency" => "CAD",
        "customer_email" => "buyer@example.com",
        "line_items" => [%{"name" => "5-pack", "unit_amount" => 5_000, "quantity" => 2}]
      },
      attrs
    )
  end

  defp event_names do
    Repo.all(from j in Oban.Job, where: j.queue == "events", select: j.args["name"])
  end

  defp paid_payment(attrs \\ %{}) do
    insert(
      :payment,
      Map.merge(
        %{
          status: :succeeded,
          payment_ref: "pi_#{System.unique_integer([:positive])}",
          amount: 5_000
        },
        attrs
      )
    )
  end

  test "connect_status reports not_connected when no account exists" do
    assert %{status: "not_connected", charges_enabled: false, account_ref: nil} =
             Payments.connect_status()
  end

  test "start_onboarding creates the account and returns a hosted URL", %{tenant: tenant} do
    actor =
      StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: :owner)

    assert {:ok, url} = Payments.start_onboarding("https://example.com/return", actor: actor)
    assert url =~ "provider.fake/onboarding/"

    account = Repo.get_by(ProviderAccount, tenant_id: tenant.id)
    assert account.provider == "fake"
    assert account.account_ref == "acct_fake_#{tenant.id}"

    assert Repo.exists?(
             from a in SportsCoachBookings.Core.Audit.Event,
               where: a.action == "payments.account.connected" and a.resource_id == ^account.id
           )
  end

  test "connect_status syncs the status from the provider" do
    insert(:provider_account, charges_enabled: false, status: "pending")

    assert %{charges_enabled: true, status: "enabled"} = Payments.connect_status()
    assert Repo.get_by(ProviderAccount, charges_enabled: true)
  end

  test "create_checkout is refused with :provider_not_ready when charges are disabled" do
    insert(:provider_account, charges_enabled: false)
    assert {:error, :provider_not_ready} = Payments.create_checkout(order())
  end

  test "create_checkout stores a pending payment and returns a redirect URL", %{tenant: tenant} do
    insert(:provider_account, charges_enabled: true, platform_fee_bps: 100)
    order = order()

    assert {:ok, redirect_url} = Payments.create_checkout(order)
    assert redirect_url =~ "provider.fake/checkout/"

    payment = Repo.get_by(Payment, order_id: order["id"])
    assert payment.status == :pending
    assert payment.amount == 10_000
    assert payment.checkout_ref == "cs_fake_#{order["id"]}"
    assert payment.tenant_id == tenant.id
  end

  test "refund records a refund, audits it, and publishes payment.refunded" do
    insert(:provider_account, charges_enabled: true)
    payment = paid_payment()

    actor =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: payment.tenant_id,
        role: :owner
      )

    assert {:ok, %Refund{} = refund} =
             Payments.refund(payment.id, Money.new(2_000, "CAD"), :requested_by_customer, actor)

    assert refund.status == :succeeded
    assert refund.amount == 2_000
    assert refund.refund_ref =~ "re_fake_"

    assert [refund] = Payments.list_refunds(payment.id)
    assert "payment.refunded" in event_names()

    audit =
      Repo.all(
        from a in SportsCoachBookings.Core.Audit.Event,
          where: a.action == "payments.refund",
          select: a.resource_id
      )

    assert refund.id in audit
  end

  test "refund refuses a payment that has no provider reference" do
    insert(:provider_account, charges_enabled: true)
    payment = insert(:payment, status: :pending, payment_ref: nil)

    actor =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: payment.tenant_id,
        role: :owner
      )

    assert {:error, :not_refundable} =
             Payments.refund(payment.id, Money.new(1_000, "CAD"), :requested_by_customer, actor)
  end
end
