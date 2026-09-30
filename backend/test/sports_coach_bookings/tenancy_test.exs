defmodule SportsCoachBookings.TenancyTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Core.TenantDomain
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Events.EventWorker
  alias SportsCoachBookings.Policies
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookings.Tenancy.Contrast

  describe "signup" do
    test "creates a tenant, owner membership, default branding, and tenant.created event" do
      attrs = %{
        "name" => "Acme Coaching",
        "slug" => "acme",
        "email" => "owner@acme.test",
        "password" => "a very long password",
        "contact_email" => "hi@acme.test"
      }

      assert {:ok,
              %{tenant: tenant, staff_user: user, membership: membership, branding: branding}} =
               Tenancy.signup(attrs)

      assert tenant.slug == "acme"
      assert tenant.currency == "CAD"
      assert tenant.timezone == "America/Toronto"
      assert user.email == "owner@acme.test"
      assert membership.role == :owner
      assert membership.status == :active
      assert branding.tenant_id == tenant.id

      assert Repo.get_by(TenantDomain, host: "acme.localhost")
      assert Tenancy.get_tenant!(tenant.id).id == tenant.id

      assert [job] = event_jobs("tenant.created")
      assert job.args["payload"]["slug"] == "acme"
    end

    test "can attach a signup to an existing logged-in user" do
      {:ok, user} =
        SportsCoachBookings.Staff.register_staff_user(%{
          "email" => "multi@acme.test",
          "password" => "a very long password"
        })

      attrs = %{"name" => "Second Tenant", "slug" => "second", "email" => "ignored@acme.test"}

      assert {:ok, %{tenant: tenant, staff_user: same}} = Tenancy.signup(attrs, staff_user: user)
      assert same.id == user.id
      assert tenant.slug == "second"
    end

    test "rejects reserved, taken, and malformed slugs" do
      assert Tenancy.slug_available?("fresh-slug")
      assert Tenancy.validate_slug("admin") == {:error, :reserved_slug}
      assert Tenancy.validate_slug("Bad_Slug") == {:error, :invalid_slug}
      insert(:tenant, slug: "taken")
      assert Tenancy.validate_slug("taken") == {:error, :slug_taken}

      assert {:error, :reserved_slug} =
               Tenancy.signup(%{
                 "name" => "x",
                 "slug" => "admin",
                 "email" => "a@b.test",
                 "password" => "a very long password"
               })
    end
  end

  describe "settings" do
    test "exposes currency_locked and updates mutable settings" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert %{currency_locked: false, tenant: %{name: _}} = Tenancy.tenant_settings(tenant)

      assert {:ok, updated} = Tenancy.update_settings(nil, %{"name" => "Renamed"})
      assert updated.name == "Renamed"

      Application.put_env(:sports_coach_bookings, :commerce_any_paid_orders, true)
      on_exit(fn -> Application.delete_env(:sports_coach_bookings, :commerce_any_paid_orders) end)

      assert Tenancy.tenant_settings(tenant).currency_locked
      assert {:error, :currency_locked} = Tenancy.update_settings(nil, %{"currency" => "USD"})
      assert {:ok, _} = Tenancy.update_settings(nil, %{"contact_email" => "new@acme.test"})
    end

    test "soft-deletes a tenant" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:ok, deleted} = Tenancy.delete_tenant(nil)
      assert deleted.status == :deleted
      assert Repo.get_by(SportsCoachBookings.Core.Audit.Event, action: "tenancy.tenant.deleted")
    end
  end

  describe "branding" do
    test "upserts branding, returns contrast warnings, and exposes public theme" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      attrs = %{
        "primary_color" => "#000000",
        "text_color" => "#eeeeee",
        "background_color" => "#ffffff",
        "logo_key" => "#{tenant.id}/logo.png",
        "font_family" => "inter"
      }

      assert {:ok, branding, warnings} = Tenancy.update_branding(nil, attrs)
      assert branding.primary_color == "#000000"
      assert warnings != []

      public = Tenancy.public_branding(tenant)
      assert public.theme.text_color == "#eeeeee"
      assert public.assets.logo_url =~ "logo.png"

      email = Tenancy.branding_for_email(tenant.id)
      assert email.tenant_name == tenant.name
      assert email.logo_url =~ "logo.png"
    end

    test "rejects invalid colours and fonts" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      assert {:error, %Ecto.Changeset{}} =
               Tenancy.update_branding(nil, %{"primary_color" => "not-a-color"})

      assert {:error, %Ecto.Changeset{}} =
               Tenancy.update_branding(nil, %{"font_family" => "comic-sans"})
    end

    test "branding_for_email works with no request tenant context" do
      tenant = insert(:tenant)
      put_tenant(tenant)
      {:ok, _, _} = Tenancy.update_branding(nil, %{"primary_color" => "#123456"})
      TenantContext.clear()

      assert %{primary_color: "#123456"} = Tenancy.branding_for_email(tenant.id)
    end
  end

  describe "tenant.created subscriber (WP-10)" do
    test "the default policy is seeded when the event is delivered" do
      tenant = insert(:tenant)
      put_tenant(tenant)

      {:ok, {:ok, job}} =
        Repo.with_tenant_tx(fn ->
          Events.publish("tenant.created", %{tenant_id: tenant.id, slug: tenant.slug})
        end)

      assert :ok = EventWorker.perform(job)
      put_tenant(tenant)
      assert %{is_default: true} = Policies.get_default_policy()
    end
  end

  describe "contrast" do
    test "computes ratios and warns on low contrast" do
      assert_in_delta Contrast.ratio("#000000", "#ffffff"), 21.0, 0.1
      assert :error = Contrast.ratio("nope", "#ffffff")

      warnings = Contrast.warnings(%{text_color: "#999999", background_color: "#ffffff"})
      assert Enum.any?(warnings, &String.contains?(&1, "WCAG AA"))
    end
  end

  defp event_jobs(name) do
    Repo.all(Oban.Job) |> Enum.filter(&(&1.args["name"] == name))
  end
end
