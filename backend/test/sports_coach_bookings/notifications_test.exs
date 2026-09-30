defmodule SportsCoachBookings.NotificationsTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Notifications.Preferences

  @assigns %{name: "Alex", action_url: "https://example.com/portal"}

  defp emails do
    Repo.all(Oban.Job) |> Enum.filter(&(&1.queue == "notifications"))
  end

  describe "branding" do
    test "renders the same template with two tenants' branding" do
      tenant_a = insert(:tenant, name: "Alpha Coaching")
      tenant_b = insert(:tenant, name: "Bravo Sports")

      put_tenant(tenant_a)

      insert(:branding,
        tenant_id: tenant_a.id,
        primary_color: "#ff0000",
        logo_key: "alpha-logo.png",
        email_footer_text: "1 Alpha Way, Toronto"
      )

      put_tenant(tenant_b)

      insert(:branding,
        tenant_id: tenant_b.id,
        primary_color: "#00ff00",
        logo_key: "bravo-logo.png",
        email_footer_text: "2 Bravo Rd, Montreal"
      )

      {:ok, rendered_a} = Notifications.render(:sample, @assigns, tenant_id: tenant_a.id)
      {:ok, rendered_b} = Notifications.render(:sample, @assigns, tenant_id: tenant_b.id)

      assert rendered_a.html =~ "Alpha Coaching"
      assert rendered_a.html =~ "#ff0000"
      assert rendered_a.html =~ "alpha-logo.png"
      assert rendered_a.html =~ "1 Alpha Way, Toronto"

      assert rendered_b.html =~ "Bravo Sports"
      assert rendered_b.html =~ "#00ff00"
      assert rendered_b.html =~ "bravo-logo.png"
      assert rendered_b.html =~ "2 Bravo Rd, Montreal"

      refute rendered_a.html == rendered_b.html
      assert rendered_a.subject == "Welcome, Alex"
      assert rendered_a.text =~ "Alex"
    end
  end

  describe "deliver/4" do
    test "inserts a message and one delivery per recipient and enqueues jobs" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:ok, %{message: message, deliveries: deliveries, idempotent: false}} =
               Notifications.deliver(
                 :sample,
                 [
                   %{type: :email, email: "one@example.com"},
                   %{type: :email, email: "two@example.com"}
                 ],
                 @assigns
               )

      assert message.template_key == "sample"
      assert message.category == :transactional
      assert message.subject == "Welcome, Alex"
      assert length(deliveries) == 2
      assert Enum.all?(deliveries, &(&1.status == :queued))

      jobs = emails()
      assert length(jobs) == 2
      assert Enum.all?(jobs, &(&1.args["tenant_id"] == tenant.id))

      assert Enum.sort(Enum.map(jobs, & &1.args["delivery_id"])) ==
               Enum.sort(Enum.map(deliveries, & &1.id))
    end

    test "idempotency_key makes a repeat a no-op with no extra jobs" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      {:ok, first} =
        Notifications.deliver(:sample, [%{type: :email, email: "a@example.com"}], @assigns,
          idempotency_key: "order-1"
        )

      {:ok, second} =
        Notifications.deliver(:sample, [%{type: :email, email: "a@example.com"}], @assigns,
          idempotency_key: "order-1"
        )

      assert second.idempotent
      assert second.message.id == first.message.id
      assert length(second.deliveries) == 1
      assert length(emails()) == 1
      assert Repo.aggregate(Message, :count) == 1
    end

    test "the same idempotency key in another tenant is independent" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      put_tenant(tenant_a)

      {:ok, first} =
        Notifications.deliver(:sample, [%{type: :email, email: "a@example.com"}], @assigns,
          idempotency_key: "shared"
        )

      put_tenant(tenant_b)

      {:ok, second} =
        Notifications.deliver(:sample, [%{type: :email, email: "a@example.com"}], @assigns,
          idempotency_key: "shared"
        )

      refute second.idempotent
      refute second.message.id == first.message.id
    end

    test "rejects unknown templates and missing assigns" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:error, {:unknown_template, "nope"}} =
               Notifications.deliver(:nope, [%{type: :email, email: "a@example.com"}], %{})

      assert {:error, {:missing_assigns, missing}} =
               Notifications.deliver(
                 :sample,
                 [%{type: :email, email: "a@example.com"}],
                 %{name: "Alex"}
               )

      assert :action_url in missing
    end

    test "requires a tenant in context" do
      TenantContext.clear()

      assert {:error, :no_tenant} =
               Notifications.deliver(:sample, [%{type: :email, email: "a@example.com"}], @assigns)
    end

    test "the legacy seam form sends to assigns[:email]" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:ok, %{deliveries: [delivery]}} =
               Notifications.deliver(
                 :customer_confirm,
                 %{email: "seam@example.com", token: "t"},
                 []
               )

      assert delivery.email == "seam@example.com"
      assert delivery.recipient_type == :email
      assert delivery.status == :queued
    end
  end

  describe "suppression" do
    test "a suppressed address is skipped and no job is enqueued" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      insert(:suppression, tenant_id: tenant.id, email: "blocked@example.com", reason: :bounce)

      {:ok, %{deliveries: [delivery]}} =
        Notifications.deliver(:sample, [%{type: :email, email: "blocked@example.com"}], @assigns)

      assert delivery.status == :suppressed
      assert emails() == []
    end

    test "password reset is exempt from suppression" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      insert(:suppression, tenant_id: tenant.id, email: "blocked@example.com", reason: :bounce)

      {:ok, %{deliveries: [delivery]}} =
        Notifications.deliver(
          :customer_reset_password,
          [%{type: :email, email: "blocked@example.com"}],
          %{email: "blocked@example.com", token: "t"}
        )

      assert delivery.status == :queued
      assert length(emails()) == 1
    end
  end

  describe "preferences" do
    test "marketing requires opt-in; transactional is always on" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      customer = insert(:customer_user, tenant_id: tenant.id)
      recipient = %{type: :customer_user, id: customer.id, email: customer.email}

      {:ok, %{deliveries: [blocked]}} =
        Notifications.deliver(:sample, [recipient], @assigns, category: :marketing)

      assert blocked.status == :suppressed

      assert {:ok, %{marketing_opt_in: true}} =
               Preferences.update(customer, %{marketing_opt_in: true})

      {:ok, %{deliveries: [allowed]}} =
        Notifications.deliver(:sample, [recipient], @assigns, category: :marketing)

      assert allowed.status == :queued

      {:ok, %{deliveries: [always]}} =
        Notifications.deliver(:sample, [recipient], @assigns, category: :transactional)

      assert always.status == :queued
    end

    test "wp-02's preference seam delegates to Notifications.Preferences" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      customer = insert(:customer_user, tenant_id: tenant.id)

      assert SportsCoachBookings.Customers.Preferences.get(customer) ==
               %{marketing_opt_in: false, operational: true, transactional: true}

      assert {:ok, %{marketing_opt_in: true}} =
               SportsCoachBookings.Customers.Preferences.update(customer, %{
                 marketing_opt_in: true
               })

      assert SportsCoachBookings.Customers.Preferences.get(customer).marketing_opt_in
    end
  end

  describe "delivery log" do
    test "returns deliveries for an email within 90 days" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      {:ok, _} =
        Notifications.deliver(:sample, [%{type: :email, email: "log@example.com"}], @assigns)

      %{data: data} = Notifications.deliveries_for_emails(["log@example.com"], %{})
      assert [%Delivery{} = delivery] = data
      assert delivery.message.template_key == "sample"
    end

    test "refuses to resend a suppressed address" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      {:ok, %{deliveries: [delivery]}} =
        Notifications.deliver(:sample, [%{type: :email, email: "blocked@example.com"}], @assigns)

      insert(:suppression, tenant_id: tenant.id, email: "blocked@example.com", reason: :complaint)

      assert {:error, :suppressed} = Notifications.resend_delivery(nil, delivery.id)
    end

    test "resending creates a new queued delivery" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      {:ok, %{deliveries: [delivery]}} =
        Notifications.deliver(:sample, [%{type: :email, email: "again@example.com"}], @assigns)

      assert {:ok, new_delivery} = Notifications.resend_delivery(nil, delivery.id)
      assert new_delivery.id != delivery.id
      assert new_delivery.status == :queued
      assert length(emails()) == 2
    end
  end

  describe "unsubscribe" do
    test "a user token turns off marketing" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      customer = insert(:customer_user, tenant_id: tenant.id)

      {:ok, _} = Preferences.update(customer, %{marketing_opt_in: true})

      token =
        Notifications.UnsubscribeToken.sign(%{
          tenant_id: tenant.id,
          subject_type: :customer_user,
          subject_id: customer.id,
          email: customer.email
        })

      assert {:ok, :unsubscribed} = Notifications.unsubscribe(token)
      refute Preferences.get(customer).marketing_opt_in
    end

    test "an invalid token is rejected" do
      assert {:error, :invalid_token} = Notifications.unsubscribe("not-a-token")
    end
  end
end
