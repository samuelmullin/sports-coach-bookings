# Seeds for local development. `mix setup` runs this.
#
# WP-00 creates the demo tenant so that the host-resolution acceptance check
# works out of the box (`demo.localhost`). Context owners add their own demo
# data for the `demo` tenant. WP-03 seeds a small catalog.

alias SportsCoachBookings.Bookings
alias SportsCoachBookings.Catalog
alias SportsCoachBookings.Commerce
alias SportsCoachBookings.Core.StaffActor
alias SportsCoachBookings.Core.Tenant
alias SportsCoachBookings.Core.TenantContext
alias SportsCoachBookings.Core.TenantDomain
alias SportsCoachBookings.Customers
alias SportsCoachBookings.Customers.CustomerUser
alias SportsCoachBookings.Customers.Household
alias SportsCoachBookings.Customers.HouseholdMember
alias SportsCoachBookings.Credits
alias SportsCoachBookings.Feedback
alias SportsCoachBookings.Inventory
alias SportsCoachBookings.Legal
alias SportsCoachBookings.Notifications.Broadcasts
alias SportsCoachBookings.Payments.ProviderAccount
alias SportsCoachBookings.Players
alias SportsCoachBookings.Policies
alias SportsCoachBookings.Repo
alias SportsCoachBookings.Scheduling
alias SportsCoachBookings.Staff
alias SportsCoachBookings.Tenancy
alias SportsCoachBookings.Waivers

tenant =
  case Repo.get_by(Tenant, slug: "demo") do
    nil ->
      Repo.insert!(%Tenant{
        name: "Demo Coaching",
        slug: "demo",
        status: :active,
        timezone: "America/Toronto",
        currency: "CAD",
        contact_email: "demo@sportscoachbookings.com"
      })

    tenant ->
      tenant
  end

for host <- ["demo.localhost", "demo.sportscoachbookings.com"] do
  unless Repo.get_by(TenantDomain, host: host) do
    Repo.insert!(%TenantDomain{tenant_id: tenant.id, host: host, primary: true})
  end
end

IO.puts("Seeded demo tenant (slug: demo).")

# Staff owner + branding (WP-01). The demo owner can log in with
# owner@sportscoachbookings.com / demo-owner-password.
demo_owner_email = "owner@sportscoachbookings.com"

demo_owner =
  case Staff.get_staff_user_by_email(demo_owner_email) do
    nil ->
      {:ok, owner} =
        Staff.register_staff_user(%{
          email: demo_owner_email,
          password: "demo-owner-password"
        })

      owner

    owner ->
      owner
  end

TenantContext.with_tenant(tenant, fn ->
  if is_nil(Staff.get_active_membership(demo_owner.id)) do
    {:ok, _membership} =
      Staff.upsert_membership(tenant.id, demo_owner.id, :owner, display_name: "Demo Owner")

    IO.puts("Seeded demo owner membership (#{demo_owner_email}).")
  else
    IO.puts("Demo owner membership already seeded; skipping.")
  end

  if is_nil(Tenancy.get_branding(tenant).id) do
    {:ok, _branding, _warnings} =
      Tenancy.update_branding(nil, %{
        "primary_color" => "#0f766e",
        "secondary_color" => "#115e59",
        "accent_color" => "#f59e0b",
        "background_color" => "#ffffff",
        "text_color" => "#111827",
        "font_family" => "inter",
        "email_footer_text" => "Demo Coaching · Halifax, NS"
      })

    IO.puts("Seeded demo branding.")
  else
    IO.puts("Demo branding already seeded; skipping.")
  end
end)

# Legal documents (portal). Default Terms of Service and Privacy Policy so the
# registration consent links and document modals work. Idempotent.
TenantContext.with_tenant(tenant, fn ->
  case Legal.seed_defaults() do
    :ok -> IO.puts("Seeded default legal documents (terms, privacy) or already present.")
    {:error, reason} -> IO.puts("Skipped legal document seeds: #{inspect(reason)}")
  end
end)

TenantContext.with_tenant(tenant, fn ->
  if Catalog.list_venues() == [] do
    for {name, city} <- [{"Northside Turf", "Halifax"}, {"Harbour Dome", "Dartmouth"}] do
      {:ok, _venue} = Catalog.create_venue(nil, %{name: name, city: city})
    end

    offering_attrs = [
      %{
        name: "1:1 Private Session",
        format: :private,
        description:
          "One-on-one coaching tailored to your player's goals. A coach works through " <>
            "technique, decision-making, and confidence at your player's pace. Ideal for " <>
            "targeted skill development or match preparation.",
        duration_minutes: 60,
        default_capacity: 1,
        drop_in_price: 12_000,
        taxable: true,
        position: 0
      },
      %{
        name: "Semi-Private (2 players)",
        format: :semi_private,
        description:
          "Small-group coaching for two players of similar age and ability. Combines " <>
            "individual attention with partner drills and small-sided games.",
        duration_minutes: 60,
        default_capacity: 2,
        drop_in_price: 8_000,
        taxable: true,
        position: 1
      },
      %{
        name: "Group U8-U10",
        format: :group,
        description:
          "A fun, high-energy session for younger players focusing on ball mastery, " <>
            "movement, and small-sided games. All abilities welcome — just bring water " <>
            "and shin pads.",
        duration_minutes: 75,
        default_capacity: 12,
        min_age: 7,
        max_age: 10,
        drop_in_price: 3_500,
        taxable: true,
        position: 2
      },
      %{
        name: "Group U11-U14",
        format: :group,
        description:
          "Technical and tactical development for older players, with progressive drills " <>
            "and match-realistic games. Builds on core skills with position-specific work.",
        duration_minutes: 90,
        default_capacity: 16,
        min_age: 11,
        max_age: 14,
        drop_in_price: 4_000,
        taxable: true,
        position: 3
      }
    ]

    for attrs <- offering_attrs do
      {:ok, offering} = Catalog.create_offering(nil, attrs)
      offering
    end

    # Packages are all offering-scoped session packs; they are seeded by the
    # idempotent pack block below (outside the venue guard) so both fresh and
    # existing databases converge on the same per-offering packs.

    {:ok, _discount} =
      Catalog.create_discount(nil, %{
        code: "WELCOME10",
        kind: :percent,
        value: 1000,
        applies_to: :all,
        active: true
      })

    {:ok, _tax_rate} =
      Catalog.create_tax_rate(nil, %{name: "HST", rate_bps: 1300, active: true})

    IO.puts("Seeded catalog: 2 venues, 4 offerings, 1 discount, 1 tax rate.")
  else
    IO.puts("Catalog already seeded; skipping.")
  end
end)

# Session packs (WP-03). Tiered packs scoped to each group offering so the
# per-offering pack UI has data. Idempotent by name and deliberately outside the
# `list_venues() == []` guard above so re-running seeds on an existing database
# still adds the packs.
TenantContext.with_tenant(tenant, fn ->
  offerings = Catalog.list_offerings()
  existing_names = Catalog.list_packages() |> Enum.map(& &1.name) |> MapSet.new()

  pack_specs = [
    {"Group U8-U10", [{3, 9_900, 180}, {5, 15_500, 240}, {10, 29_000, 365}]},
    {"Group U11-U14", [{3, 11_400, 180}, {5, 18_000, 240}, {10, 34_000, 365}]},
    {"1:1 Private Session", [{5, 55_000, 240}, {10, 100_000, 365}]},
    {"Semi-Private (2 players)", [{5, 40_000, 240}, {10, 75_000, 365}]}
  ]

  created =
    for {offering_name, tiers} <- pack_specs,
        offering = Enum.find(offerings, &(&1.name == offering_name)),
        offering,
        {credits, price, validity_days} <- tiers,
        name = "#{offering_name} #{credits}-Session Pack",
        not MapSet.member?(existing_names, name),
        reduce: 0 do
      acc ->
        {:ok, _package} =
          Catalog.create_package(nil, %{
            name: name,
            description: "#{credits} sessions for #{offering_name}.",
            credit_quantity: credits,
            price: price,
            validity_days: validity_days,
            visible_in_portal: true,
            taxable: true,
            position: credits,
            offering_ids: [offering.id]
          })

        acc + 1
    end

  if created > 0 do
    IO.puts("Seeded #{created} offering-scoped session pack(s).")
  else
    IO.puts("Offering-scoped session packs already seeded; skipping.")
  end
end)

# Customers (WP-02). The demo household uses deterministic ids that the Players
# and Waivers seeds also reference, now backed by real `households`,
# `customer_users`, and `household_members` rows.
#
# Credentials:
#   primary manager: parent@example.com / demo-customer-password
#   co-manager:      luis@example.com   / demo-customer-password
demo_household = "01900000-0000-7000-8000-000000000001"
demo_customer_user = "01900000-0000-7000-8000-000000000002"
demo_second_user = "01900000-0000-7000-8000-000000000003"

TenantContext.with_tenant(tenant, fn ->
  {:ok, _} =
    Repo.with_tenant_tx(fn ->
      household = Customers.get_household(demo_household)

      if is_nil(household) do
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        household =
          Repo.insert!(%Household{
            id: demo_household,
            tenant_id: tenant.id,
            name: "Reyes Household"
          })

        primary =
          %CustomerUser{id: demo_customer_user, tenant_id: tenant.id}
          |> CustomerUser.registration_changeset(%{
            "first_name" => "Dana",
            "last_name" => "Reyes",
            "email" => "parent@example.com",
            "phone" => "+19025550111",
            "password" => "demo-customer-password",
            "accept_terms" => true,
            "accept_privacy" => true
          })
          |> Ecto.Changeset.put_change(:confirmed_at, now)
          |> Repo.insert!()

        Repo.insert!(
          HouseholdMember.changeset(%HouseholdMember{}, %{
            tenant_id: tenant.id,
            household_id: household.id,
            customer_user_id: primary.id,
            role: :primary,
            relationship: "self"
          })
        )

        manager =
          %CustomerUser{id: demo_second_user, tenant_id: tenant.id}
          |> CustomerUser.registration_changeset(%{
            "first_name" => "Luis",
            "last_name" => "Reyes",
            "email" => "luis@example.com",
            "phone" => "+19025550122",
            "password" => "demo-customer-password",
            "accept_terms" => true,
            "accept_privacy" => true
          })
          |> Ecto.Changeset.put_change(:confirmed_at, now)
          |> Repo.insert!()

        Repo.insert!(
          HouseholdMember.changeset(%HouseholdMember{}, %{
            tenant_id: tenant.id,
            household_id: household.id,
            customer_user_id: manager.id,
            role: :manager,
            relationship: "grandparent"
          })
        )

        IO.puts(
          "Seeded demo household #{demo_household} (primary parent@example.com, " <>
            "manager luis@example.com; password: demo-customer-password)."
        )
      else
        IO.puts("Customers already seeded; skipping.")
      end

      :ok
    end)
end)

# Players (WP-06). The household row above (owned by WP-02) now exists; until
# the FK is added (see the RFC) `players.household_id` remains a plain uuid.
TenantContext.with_tenant(tenant, fn ->
  if Players.list_for_household(demo_household) == [] do
    {:ok, adult} =
      Players.create_player(nil, %{
        household_id: demo_household,
        first_name: "Dana",
        last_name: "Reyes",
        date_of_birth: ~D[1990-06-15],
        is_self: true
      })

    {:ok, minor} =
      Players.create_player(nil, %{
        household_id: demo_household,
        first_name: "Marco",
        last_name: "Reyes",
        date_of_birth: ~D[2014-03-22]
      })

    for player <- [adult, minor] do
      {:ok, _} =
        Players.create_emergency_contact(player, %{
          name: "Dana Reyes",
          relationship: "Parent",
          phone: "+19025550111",
          priority: 1
        })
    end

    {:ok, _} =
      Players.create_emergency_contact(minor, %{
        name: "Luis Reyes",
        relationship: "Uncle",
        phone: "+19025550122",
        priority: 2
      })

    {:ok, _} =
      Players.create_authorized_pickup(minor, %{
        name: "Luis Reyes",
        relationship: "Uncle",
        phone: "+19025550122"
      })

    {:ok, _} =
      Players.upsert_profile(nil, minor, %{
        home_club: "Halifax City",
        team: "U12",
        preferred_positions: ["CM", "AM"],
        dominant_foot: "right",
        goals: "Play rep soccer"
      })

    {:ok, _} =
      Players.upsert_medical_info(nil, minor, %{
        allergies: "Peanuts",
        medications: "Salbutamol inhaler",
        notes: "Carries an EpiPen in the kit bag"
      })

    IO.puts("Seeded players: household #{demo_household} with 2 players.")
  else
    IO.puts("Players already seeded; skipping.")
  end
end)

# Waivers (WP-07). One published all-bookings waiver (re-sign required) and one
# offering-scoped waiver, plus a signature for the minor player.
TenantContext.with_tenant(tenant, fn ->
  if Waivers.list_templates() == [] do
    offerings = Catalog.list_offerings()
    scoped_offering = Enum.find(offerings, &(&1.format == :private)) || List.first(offerings)

    {:ok, general} =
      Waivers.create_template(nil, %{
        "name" => "General Liability Waiver",
        "scope" => "all_bookings",
        "require_resign_on_new_version" => true
      })

    {:ok, general_draft} =
      Waivers.create_version(nil, general.id, %{
        "body_markdown" =>
          "I acknowledge the risks of participating in sports coaching and " <>
            "release Demo Coaching from liability, to the extent permitted by law."
      })

    {:ok, general_published} = Waivers.publish_version(nil, general_draft.id)

    soccer =
      if scoped_offering do
        {:ok, template} =
          Waivers.create_template(nil, %{
            "name" => "Soccer Program Release",
            "scope" => "offerings",
            "offering_ids" => [scoped_offering.id]
          })

        template
      end

    if soccer do
      {:ok, soccer_draft} =
        Waivers.create_version(nil, soccer.id, %{
          "body_markdown" =>
            "Additional release for the Soccer Program, including facility rules " <>
              "and equipment use."
        })

      {:ok, _soccer_published} = Waivers.publish_version(nil, soccer_draft.id)
    end

    players = Players.list_for_household(demo_household)
    player = Enum.find(players, &(!&1.is_self)) || List.first(players)

    if player do
      {:ok, _signature} =
        Waivers.sign(nil, player.id, general_published.id, %{
          "content_sha256" => general_published.content_sha256,
          "customer_user_id" => demo_customer_user,
          "signer_name_typed" => "Dana Reyes",
          "signer_relationship" => "Parent",
          "consent_checkbox" => true,
          "ip" => "127.0.0.1",
          "user_agent" => "seed"
        })
    end

    IO.puts("Seeded waivers: 1 all-bookings + 1 offering-scoped, 1 signature.")
  else
    IO.puts("Waivers already seeded; skipping.")
  end
end)

# Policies (WP-10). A default cancellation policy for the demo tenant.
case Policies.seed_default_policy(tenant.id) do
  {:ok, :seeded} -> IO.puts("Seeded default cancellation policy.")
  {:ok, :already_seeded} -> IO.puts("Cancellation policies already seeded; skipping.")
  {:error, reason} -> raise "failed to seed cancellation policy: #{inspect(reason)}"
end

# Payments (WP-04). A connected provider account so the demo tenant's checkout
# path is ready. There are no real Stripe keys in this environment, so the
# account is seeded directly with a deterministic ref; `Payments.connect_status/0`
# falls back to the persisted status when the provider cannot be reached.
TenantContext.with_tenant(tenant, fn ->
  Repo.with_tenant_tx(fn ->
    if is_nil(Repo.get_by(ProviderAccount, tenant_id: tenant.id)) do
      Repo.insert!(%ProviderAccount{
        tenant_id: tenant.id,
        provider: "stripe",
        account_ref: "acct_demo_connect",
        status: "enabled",
        charges_enabled: true,
        payouts_enabled: true,
        requirements: %{},
        platform_fee_bps: 0
      })

      IO.puts("Seeded demo provider account (stripe / acct_demo_connect).")
    else
      IO.puts("Provider account already seeded; skipping.")
    end
  end)
end)

# Inventory (WP-08). Two products with size variants and opening stock so the
# portal shop and the staff pickup queue are usable in the demo tenant.
TenantContext.with_tenant(tenant, fn ->
  if Inventory.list_products() == [] do
    seed_product = fn attrs, variants ->
      {:ok, product} = Inventory.create_product(nil, attrs)

      for %{size: size, sku: sku, price: price, quantity: quantity} <- variants do
        {:ok, variant} =
          Inventory.create_variant(nil, product.id, %{
            "sku" => sku,
            "price" => price,
            "option_values" => %{"size" => size},
            "low_stock_threshold" => 2
          })

        {:ok, _movement} =
          Inventory.receive_stock(nil, variant.id, %{
            "quantity" => quantity,
            "note" => "opening stock"
          })
      end

      product
    end

    seed_product.(
      %{
        "name" => "Home Jersey",
        "description" => "Dry-fit match jersey in club navy.",
        "taxable" => true,
        "position" => 0
      },
      [
        %{size: "YM", sku: "JER-YM", price: 4_500, quantity: 10},
        %{size: "YL", sku: "JER-YL", price: 4_500, quantity: 10},
        %{size: "AS", sku: "JER-AS", price: 5_000, quantity: 10}
      ]
    )

    seed_product.(
      %{
        "name" => "Goalkeeper Gloves",
        "description" => "Grip gloves with reinforced palms.",
        "taxable" => true,
        "position" => 1
      },
      [
        %{size: "S", sku: "GK-S", price: 3_500, quantity: 6},
        %{size: "M", sku: "GK-M", price: 3_500, quantity: 6}
      ]
    )

    IO.puts("Seeded inventory: 2 products with size variants and stock.")
  else
    IO.puts("Inventory already seeded; skipping.")
  end
end)

# Scheduling (WP-11). A demo coach plus a few weeks of sessions across the seeded
# offerings and venues, including one cancelled session.
demo_coach_email = "coach@sportscoachbookings.com"

demo_coach =
  case Staff.get_staff_user_by_email(demo_coach_email) do
    nil ->
      {:ok, coach} =
        Staff.register_staff_user(%{email: demo_coach_email, password: "demo-coach-password"})

      coach

    coach ->
      coach
  end

TenantContext.with_tenant(tenant, fn ->
  if is_nil(Staff.get_active_membership(demo_coach.id)) do
    {:ok, _membership} =
      Staff.upsert_membership(tenant.id, demo_coach.id, :coach, display_name: "Coach Sam")

    IO.puts("Seeded demo coach (#{demo_coach_email}).")
  end
end)

TenantContext.with_tenant(tenant, fn ->
  now = DateTime.utc_now()
  today = Date.utc_today()
  window = %{from: now, to: DateTime.add(now, 60 * 86_400)}

  if Scheduling.list_sessions(window) == [] do
    offerings = Catalog.list_offerings() |> Enum.sort_by(& &1.position)
    venues = Catalog.list_venues() |> Enum.sort_by(& &1.name)
    coach_ids = Staff.list_coaches() |> Enum.map(& &1.id)

    [private, semi_private, group_young, group_old] = offerings
    [northside, harbour] = venues

    # 4 weeks of the younger group on Tuesdays, in the venue's local time.
    {:ok, _series} =
      Scheduling.create_series(nil, %{
        offering_id: group_young.id,
        venue_id: northside.id,
        weekdays: [2],
        start_time_local: "17:00",
        duration_minutes: 75,
        starts_on: today,
        ends_on: Date.add(today, 28),
        coach_ids: coach_ids
      })

    # 4 weeks of the older group on Thursdays.
    {:ok, _series} =
      Scheduling.create_series(nil, %{
        offering_id: group_old.id,
        venue_id: harbour.id,
        weekdays: [4],
        start_time_local: "18:30",
        duration_minutes: 90,
        starts_on: today,
        ends_on: Date.add(today, 28),
        coach_ids: coach_ids
      })

    # A couple of single sessions, including a cancelled one.
    {:ok, _private_session} =
      Scheduling.create_session(nil, %{
        offering_id: private.id,
        venue_id: northside.id,
        starts_at: DateTime.add(now, 4 * 86_400) |> DateTime.to_iso8601(),
        capacity: 1,
        coach_ids: coach_ids
      })

    {:ok, _semi_session} =
      Scheduling.create_session(nil, %{
        offering_id: semi_private.id,
        venue_id: harbour.id,
        starts_at: DateTime.add(now, 6 * 86_400) |> DateTime.to_iso8601(),
        capacity: 2,
        coach_ids: coach_ids
      })

    {:ok, %{session: cancelled}} =
      Scheduling.create_session(nil, %{
        offering_id: group_young.id,
        venue_id: northside.id,
        starts_at: DateTime.add(now, 8 * 86_400) |> DateTime.to_iso8601(),
        coach_ids: coach_ids
      })

    {:ok, _} = Scheduling.cancel_session(nil, cancelled.id, "Coach unavailable")

    IO.puts("Seeded scheduling: 2 series (4 weeks each) + 3 single sessions (1 cancelled).")
  else
    IO.puts("Scheduling already seeded; skipping.")
  end
end)

# Credits (WP-12). An initial administrator grant so the demo household has a
# usable balance in the portal.
TenantContext.with_tenant(tenant, fn ->
  if Credits.list_lots(demo_household) == [] do
    {:ok, _lot} =
      Credits.grant_complimentary(nil, demo_household, %{
        amount: 4,
        note: "demo welcome credits"
      })

    IO.puts("Seeded 4 demo credits for household #{demo_household}.")
  else
    IO.puts("Credits already seeded; skipping.")
  end
end)

# Commerce (WP-13). A paid offline order (package purchase) and an open cart for
# the demo household so the portal order history and cart are usable.
TenantContext.with_tenant(tenant, fn ->
  paid? =
    demo_household
    |> Commerce.list_orders_for_household()
    |> Enum.any?(&(&1.status == :paid))

  if paid? do
    IO.puts("Commerce paid order already seeded; skipping.")
  else
    case Catalog.list_packages() do
      [package | _] ->
        {:ok, order} =
          Commerce.create_offline_order(nil, %{
            household_id: demo_household,
            lines: [%{type: :package, ref_id: package.id, quantity: 1}]
          })

        IO.puts("Seeded paid offline order #{order.number} for #{demo_household}.")

      [] ->
        IO.puts("No packages to seed a demo order.")
    end
  end

  if Commerce.get_cart(demo_household) do
    IO.puts("Commerce pending cart already seeded; skipping.")
  else
    case Inventory.list_products() do
      [product | _] ->
        case Inventory.list_variants(product.id) do
          [variant | _] ->
            _ = Commerce.add_product_to_cart(demo_household, variant.id, 1)
            IO.puts("Seeded a pending cart for #{demo_household}.")

          [] ->
            :ok
        end

      [] ->
        :ok
    end
  end
end)

# Bookings (WP-14). Two confirmed bookings (credits) and one held booking (paid)
# for the demo household's minor player, on future group sessions. Idempotent.
TenantContext.with_tenant(tenant, fn ->
  if Bookings.list_for_household(demo_household) == [] do
    players = Players.list_for_household(demo_household)
    minor = Enum.find(players, &(!&1.is_self)) || List.first(players)

    offerings = Catalog.list_offerings() |> Enum.sort_by(& &1.position)
    offering = Enum.at(offerings, 3) || List.last(offerings)
    now = DateTime.utc_now()

    sessions =
      if offering do
        Scheduling.list_sessions(%{
          offering_id: offering.id,
          from: now,
          to: DateTime.add(now, 40, :day)
        })
        |> Enum.filter(&(&1.status == :scheduled))
        |> Enum.take(3)
      else
        []
      end

    actor = StaffActor.new(staff_user_id: demo_owner.id, tenant_id: tenant.id, role: :owner)

    if minor && length(sessions) == 3 do
      Enum.zip(sessions, [:credits, :credits, :paid])
      |> Enum.each(fn {session, method} ->
        case Bookings.book(actor, minor.id, session.id, method) do
          {:ok, _booking} -> :ok
          {:error, reason} -> IO.puts("Skipped a demo booking: #{inspect(reason)}")
        end
      end)

      IO.puts("Seeded demo bookings (2 confirmed + 1 held) for #{demo_household}.")
    else
      IO.puts("Not enough future group sessions to seed bookings; skipping.")
    end
  else
    IO.puts("Bookings already seeded; skipping.")
  end
end)

# Feedback (WP-15). Default skill tags plus one shared coach feedback row on a
# demo booking, so the admin coach view and the portal player feedback page have
# data. Idempotent.
TenantContext.with_tenant(tenant, fn ->
  :ok = Feedback.ensure_default_skill_tags()

  coach_membership = Staff.get_active_membership(demo_coach.id)

  booked =
    demo_household
    |> Bookings.list_for_household()
    |> Enum.find(fn entry -> entry.booking.status in [:confirmed, :held] end)

  player_id = booked && booked.booking.player_id

  if player_id && Feedback.list_for_player(player_id) != [] do
    IO.puts("Feedback already seeded; skipping.")
  else
    owner = StaffActor.new(staff_user_id: demo_owner.id, tenant_id: tenant.id, role: :owner)

    case {booked, coach_membership} do
      {%{session: session, booking: booking}, %{} = membership} ->
        {:ok, _feedback} =
          Feedback.create_feedback(owner, %{
            session_id: session.id,
            player_id: booking.player_id,
            coach_id: membership.id,
            body: "Great energy today — the first touch is improving.",
            skill_ratings: %{"first_touch" => 4, "passing" => 3, "work_rate" => 5},
            focus_next: "Scanning before receiving the ball.",
            visibility: "shared"
          })

        IO.puts("Seeded demo coach feedback for player #{booking.player_id}.")

      _ ->
        IO.puts("No demo booking/coach to seed feedback; skipping.")
    end
  end
end)

# Broadcasts (WP-17). A draft marketing broadcast for the demo tenant so the
# admin broadcast list and preview have data. Idempotent.
TenantContext.with_tenant(tenant, fn ->
  if Broadcasts.list_broadcasts().data == [] do
    {:ok, _broadcast} =
      Broadcasts.create_broadcast(
        StaffActor.new(staff_user_id: demo_owner.id, tenant_id: tenant.id, role: :owner),
        %{
          "subject" => "Fall programs are open",
          "body_markdown" =>
            "# Fall programs are open\n\nRegistration for the fall season is now live. " <>
              "Book your sessions in the portal.\n\n- New U12 group times\n- More 1:1 slots",
          "category" => "marketing",
          "segment" => %{"match" => "all", "conditions" => []}
        }
      )

    IO.puts("Seeded a draft demo broadcast.")
  else
    IO.puts("Broadcasts already seeded; skipping.")
  end
end)
