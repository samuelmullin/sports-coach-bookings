defmodule SportsCoachBookings.Factory do
  @moduledoc """
  ExMachina factories.

  Context owners add factories for their own schemas. Factories that build
  tenant-scoped records must be given a `tenant_id` (or a `:tenant`) and run
  with that tenant in context (see `SportsCoachBookings.DataCase.put_tenant/1`).
  """

  use ExMachina.Ecto, repo: SportsCoachBookings.Repo

  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Bookings.BookingEvent
  alias SportsCoachBookings.Catalog.Discount
  alias SportsCoachBookings.Catalog.DiscountRedemption
  alias SportsCoachBookings.Catalog.DiscountTarget
  alias SportsCoachBookings.Catalog.Offering
  alias SportsCoachBookings.Catalog.Package
  alias SportsCoachBookings.Catalog.PackageOffering
  alias SportsCoachBookings.Catalog.TaxRate
  alias SportsCoachBookings.Catalog.Venue
  alias SportsCoachBookings.Commerce.Cart
  alias SportsCoachBookings.Commerce.CartLine
  alias SportsCoachBookings.Commerce.Order
  alias SportsCoachBookings.Commerce.OrderLine
  alias SportsCoachBookings.Core.Audit.Event, as: AuditEvent
  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Core.TenantDomain
  alias SportsCoachBookings.Credits.CreditLedgerEntry
  alias SportsCoachBookings.Credits.CreditLot
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.CustomerUserToken
  alias SportsCoachBookings.Customers.Household
  alias SportsCoachBookings.Customers.HouseholdInvite
  alias SportsCoachBookings.Customers.HouseholdMember
  alias SportsCoachBookings.Feedback.Revision
  alias SportsCoachBookings.Feedback.SessionFeedback
  alias SportsCoachBookings.Feedback.SkillTag
  alias SportsCoachBookings.Inventory.Fulfillment
  alias SportsCoachBookings.Inventory.Product
  alias SportsCoachBookings.Inventory.ProductVariant
  alias SportsCoachBookings.Inventory.StockLevel
  alias SportsCoachBookings.Inventory.StockMovement
  alias SportsCoachBookings.Legal.LegalDocument
  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast
  alias SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.DeliveryRef
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Notifications.NotificationPreference
  alias SportsCoachBookings.Notifications.Suppression
  alias SportsCoachBookings.Payments.Payment
  alias SportsCoachBookings.Payments.ProviderAccount
  alias SportsCoachBookings.Payments.Refund
  alias SportsCoachBookings.Players.AuthorizedPickup
  alias SportsCoachBookings.Players.EmergencyContact
  alias SportsCoachBookings.Players.MedicalInfo
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Players.PlayerPositionOption
  alias SportsCoachBookings.Players.PlayerProfile
  alias SportsCoachBookings.Policies.CancellationPolicy
  alias SportsCoachBookings.Policies.OfferingPolicyAssignment
  alias SportsCoachBookings.Policies.Rules
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Reservations.Reservation
  alias SportsCoachBookings.Reservations.ReservationSession
  alias SportsCoachBookings.Scheduling.Session
  alias SportsCoachBookings.Scheduling.SessionCoach
  alias SportsCoachBookings.Scheduling.SessionSeries
  alias SportsCoachBookings.Staff.Membership
  alias SportsCoachBookings.Staff.Password
  alias SportsCoachBookings.Staff.StaffInvite
  alias SportsCoachBookings.Staff.StaffUser
  alias SportsCoachBookings.Staff.StaffUserToken
  alias SportsCoachBookings.Tenancy.Branding
  alias SportsCoachBookings.Waivers.WaiverSignature
  alias SportsCoachBookings.Waivers.WaiverTemplate
  alias SportsCoachBookings.Waivers.WaiverTemplateOffering
  alias SportsCoachBookings.Waivers.WaiverVersion

  @waiver_body "I agree to participate and accept the risks."

  def tenant_factory do
    seq = sequence(:tenant_seq, & &1)

    %Tenant{
      name: "Coaching Co #{seq}",
      slug: "coaching-co-#{seq}",
      status: :active,
      timezone: "America/Toronto",
      currency: "CAD",
      contact_email: "hello#{seq}@example.com"
    }
  end

  def tenant_domain_factory do
    %TenantDomain{
      host: "#{sequence(:host_seq, & &1)}.localhost",
      primary: false,
      tenant: build(:tenant)
    }
  end

  def audit_event_factory do
    %AuditEvent{
      action: "test.action",
      metadata: %{},
      tenant_id: nil
    }
  end

  def venue_factory do
    %Venue{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Field #{sequence(:venue_seq, & &1)}",
      timezone: "America/Toronto",
      active: true
    }
  end

  def offering_factory do
    seq = sequence(:offering_seq, & &1)

    %Offering{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Class #{seq}",
      slug: "class-#{seq}",
      format: :group,
      duration_minutes: 60,
      default_capacity: 8,
      credit_cost: 1,
      bookable_until_minutes_before: 60,
      active: true,
      position: seq,
      taxable: false
    }
  end

  def package_factory do
    %Package{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Pack #{sequence(:package_seq, & &1)}",
      credit_quantity: 5,
      price: 10_000,
      taxable: false,
      active: true,
      visible_in_portal: true,
      position: 0
    }
  end

  def package_offering_factory do
    %PackageOffering{tenant_id: TenantContext.get_tenant_id()}
  end

  def discount_factory do
    %Discount{
      tenant_id: TenantContext.get_tenant_id(),
      code: "SAVE#{sequence(:discount_seq, & &1)}",
      kind: :percent,
      value: 1000,
      applies_to: :all,
      active: true
    }
  end

  def discount_target_factory do
    %DiscountTarget{tenant_id: TenantContext.get_tenant_id()}
  end

  def discount_redemption_factory do
    %DiscountRedemption{tenant_id: TenantContext.get_tenant_id()}
  end

  def tax_rate_factory do
    %TaxRate{
      tenant_id: TenantContext.get_tenant_id(),
      name: "HST",
      rate_bps: 1300,
      active: true
    }
  end

  def player_factory do
    %Player{
      tenant_id: TenantContext.get_tenant_id(),
      household_id: insert(:household).id,
      first_name: "Sam",
      last_name: "Player #{sequence(:player_seq, & &1)}",
      date_of_birth: ~D[2015-05-01],
      is_self: false,
      active: true,
      no_pickup_restrictions: false
    }
  end

  def player_profile_factory do
    %PlayerProfile{
      tenant_id: TenantContext.get_tenant_id(),
      preferred_positions: [],
      interests: []
    }
  end

  def player_position_option_factory do
    code = "P#{sequence(:position_seq, & &1)}"

    %PlayerPositionOption{
      tenant_id: TenantContext.get_tenant_id(),
      code: code,
      label: code,
      position: 0,
      active: true
    }
  end

  def emergency_contact_factory do
    %EmergencyContact{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Emergency Contact",
      relationship: "Parent",
      phone: "+15555550100",
      priority: 1
    }
  end

  def authorized_pickup_factory do
    %AuthorizedPickup{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Authorized Adult",
      relationship: "Grandparent",
      phone: "+15555550101"
    }
  end

  def medical_info_factory do
    %MedicalInfo{
      tenant_id: TenantContext.get_tenant_id(),
      allergies: nil,
      conditions: nil,
      medications: nil,
      notes: nil,
      has_medical_info: false
    }
  end

  def cancellation_policy_factory do
    %CancellationPolicy{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Policy #{sequence(:cancellation_policy_seq, & &1)}",
      is_default: false,
      version: 1,
      active: true,
      customer_facing_summary: "Cancel at least 24 hours before your session.",
      rules: Rules.default()
    }
  end

  def offering_policy_assignment_factory do
    %OfferingPolicyAssignment{
      tenant_id: TenantContext.get_tenant_id(),
      offering_id: Ecto.UUID.generate(),
      cancellation_policy: build(:cancellation_policy)
    }
  end

  def waiver_template_factory do
    %WaiverTemplate{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Liability Waiver #{sequence(:waiver_template_seq, & &1)}",
      scope: :all_bookings,
      require_resign_on_new_version: false,
      active: true
    }
  end

  def waiver_template_offering_factory do
    %WaiverTemplateOffering{
      tenant_id: TenantContext.get_tenant_id()
    }
  end

  def waiver_version_factory do
    %WaiverVersion{
      tenant_id: TenantContext.get_tenant_id(),
      waiver_template: build(:waiver_template),
      version: sequence(:waiver_version_seq, & &1),
      body_markdown: @waiver_body,
      status: :draft,
      content_sha256: SportsCoachBookings.Waivers.hash_body(@waiver_body)
    }
  end

  def waiver_signature_factory do
    %WaiverSignature{
      tenant_id: TenantContext.get_tenant_id(),
      waiver_version: build(:waiver_version),
      player_id: Ecto.UUID.generate(),
      customer_user_id: Ecto.UUID.generate(),
      signer_name_typed: "Dana Reyes",
      signer_relationship: "Parent",
      consent_checkbox: true,
      signed_at: DateTime.utc_now(),
      ip: "127.0.0.1",
      user_agent: "ExUnit",
      content_sha256: SportsCoachBookings.Waivers.hash_body(@waiver_body)
    }
  end

  def legal_document_factory do
    %LegalDocument{
      tenant_id: TenantContext.get_tenant_id(),
      kind: "terms",
      title: "Terms of Service",
      body_markdown: "# Terms of Service\n\nBe excellent to each other.",
      version: sequence(:legal_document_version, & &1),
      active: false
    }
  end

  def session_series_factory do
    %SessionSeries{
      tenant_id: TenantContext.get_tenant_id(),
      weekdays: [2],
      start_time_local: ~T[17:00:00],
      duration_minutes: 60,
      starts_on: ~D[2026-01-06],
      ends_on: ~D[2026-02-24],
      timezone: "America/Toronto",
      offering_id: Ecto.UUID.generate(),
      venue_id: Ecto.UUID.generate()
    }
  end

  def session_factory do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(sequence(:session_seq, & &1) * 86_400, :second)
      |> DateTime.truncate(:microsecond)

    %Session{
      tenant_id: TenantContext.get_tenant_id(),
      offering_id: Ecto.UUID.generate(),
      venue_id: Ecto.UUID.generate(),
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3600, :second),
      capacity: 8,
      booked_count: 0,
      held_count: 0,
      status: :scheduled,
      visibility: :public
    }
  end

  def session_coach_factory do
    %SessionCoach{
      tenant_id: TenantContext.get_tenant_id(),
      session: build(:session),
      membership_id: Ecto.UUID.generate(),
      lead: false
    }
  end

  def staff_user_factory do
    seq = sequence(:staff_user_seq, & &1)

    %StaffUser{
      email: "staff#{seq}@example.com",
      hashed_password: Password.hash("correct horse battery staple"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  def staff_user_token_factory do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    %StaffUserToken{
      staff_user: build(:staff_user),
      context: "session",
      token: StaffUserToken.hash(token)
    }
  end

  def membership_factory do
    %Membership{
      tenant_id: TenantContext.get_tenant_id(),
      staff_user: build(:staff_user),
      role: :coach,
      status: :active
    }
  end

  def branding_factory do
    %Branding{
      tenant_id: TenantContext.get_tenant_id(),
      primary_color: "#1d4ed8",
      secondary_color: "#9333ea",
      accent_color: "#f59e0b",
      background_color: "#ffffff",
      text_color: "#111827",
      font_family: "inter",
      social_links: %{}
    }
  end

  def staff_invite_factory do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    %StaffInvite{
      tenant_id: TenantContext.get_tenant_id(),
      email: "invitee#{sequence(:staff_invite_seq, & &1)}@example.com",
      role: :coach,
      token_hash: StaffUserToken.hash(token),
      expires_at: DateTime.add(DateTime.utc_now(), 7, :day) |> DateTime.truncate(:microsecond)
    }
  end

  def customer_user_factory do
    seq = sequence(:customer_user_seq, & &1)

    %CustomerUser{
      tenant_id: TenantContext.get_tenant_id(),
      email: "customer#{seq}@example.com",
      hashed_password: Password.hash("correct horse battery staple"),
      first_name: "Casey",
      last_name: "Customer #{seq}",
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      active: true,
      terms_version: "2026-09-28",
      privacy_version: "2026-09-28"
    }
  end

  def customer_user_token_factory do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    %CustomerUserToken{
      tenant_id: TenantContext.get_tenant_id(),
      customer_user: build(:customer_user),
      context: "session",
      token: CustomerUserToken.hash(token)
    }
  end

  def household_factory do
    %Household{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Household #{sequence(:household_seq, & &1)}"
    }
  end

  def household_member_factory do
    %HouseholdMember{
      tenant_id: TenantContext.get_tenant_id(),
      household: build(:household),
      customer_user: build(:customer_user),
      role: :manager,
      relationship: "parent"
    }
  end

  def household_invite_factory do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    %HouseholdInvite{
      tenant_id: TenantContext.get_tenant_id(),
      household: build(:household),
      email: "co-manager#{sequence(:household_invite_seq, & &1)}@example.com",
      relationship: "grandparent",
      token_hash: CustomerUserToken.hash(token),
      expires_at: DateTime.add(DateTime.utc_now(), 7, :day) |> DateTime.truncate(:microsecond)
    }
  end

  def message_factory do
    %Message{
      tenant_id: TenantContext.get_tenant_id(),
      template_key: "sample",
      category: :transactional,
      subject: "Sample subject #{sequence(:message_seq, & &1)}",
      assigns: %{"name" => "Alex", "action_url" => "https://example.com"}
    }
  end

  def delivery_factory do
    tenant_id = TenantContext.get_tenant_id()

    message =
      Repo.insert!(%Message{
        tenant_id: tenant_id,
        template_key: "sample",
        category: :transactional,
        subject: "Delivery fixture",
        assigns: %{"name" => "Alex", "action_url" => "https://example.com"}
      })

    %Delivery{
      tenant_id: tenant_id,
      message_id: message.id,
      recipient_type: :email,
      email: "delivery#{sequence(:delivery_seq, & &1)}@example.com",
      status: :queued
    }
  end

  def delivery_ref_factory do
    %DeliveryRef{
      provider: "resend",
      provider_ref: "ref-#{sequence(:delivery_ref_seq, & &1)}",
      tenant_id: TenantContext.get_tenant_id(),
      delivery_id: Ecto.UUID.generate()
    }
  end

  def suppression_factory do
    %Suppression{
      tenant_id: TenantContext.get_tenant_id(),
      email: "suppressed#{sequence(:suppression_seq, & &1)}@example.com",
      reason: :bounce
    }
  end

  def notification_preference_factory do
    %NotificationPreference{
      tenant_id: TenantContext.get_tenant_id(),
      subject_type: :customer_user,
      subject_id: Ecto.UUID.generate(),
      marketing_opt_in: false
    }
  end

  def broadcast_factory do
    %Broadcast{
      tenant_id: TenantContext.get_tenant_id(),
      subject: "Broadcast #{sequence(:broadcast_seq, & &1)}",
      body_markdown: "# Hello\n\nSome **news**.",
      category: :marketing,
      segment: %{"match" => "all", "conditions" => []},
      status: :draft,
      recipient_count: 0,
      stats: %{}
    }
  end

  def broadcast_recipient_factory do
    %BroadcastRecipient{
      tenant_id: TenantContext.get_tenant_id(),
      broadcast: build(:broadcast),
      recipient_type: :customer_user,
      recipient_id: Ecto.UUID.generate(),
      email: "broadcast#{sequence(:broadcast_recipient_seq, & &1)}@example.com",
      status: :pending,
      batch_index: 0
    }
  end

  def provider_account_factory do
    %ProviderAccount{
      tenant_id: TenantContext.get_tenant_id(),
      provider: "fake",
      account_ref: "acct_fake_#{sequence(:provider_account_seq, & &1)}",
      status: "enabled",
      charges_enabled: true,
      payouts_enabled: true,
      requirements: %{},
      platform_fee_bps: 0
    }
  end

  def payment_factory do
    %Payment{
      tenant_id: TenantContext.get_tenant_id(),
      provider: "fake",
      order_id: Ecto.UUID.generate(),
      checkout_ref: "cs_fake_#{sequence(:payment_seq, & &1)}",
      amount: 10_000,
      status: :pending,
      raw: %{}
    }
  end

  def refund_factory do
    %Refund{
      tenant_id: TenantContext.get_tenant_id(),
      payment: build(:payment),
      amount: 1_000,
      reason: "requested_by_customer",
      refund_ref: "re_fake_#{sequence(:refund_seq, & &1)}",
      status: :succeeded
    }
  end

  def product_factory do
    %Product{
      tenant_id: TenantContext.get_tenant_id(),
      name: "Product #{sequence(:product_seq, & &1)}",
      description: "Merch",
      image_keys: [],
      taxable: true,
      active: true,
      visible_in_portal: true,
      position: 0
    }
  end

  def product_variant_factory do
    %ProductVariant{
      tenant_id: TenantContext.get_tenant_id(),
      product: build(:product),
      sku: "SKU-#{sequence(:variant_seq, & &1)}",
      option_values: %{"size" => "YM"},
      price: 2_500,
      low_stock_threshold: 2,
      active: true
    }
  end

  def stock_level_factory do
    %StockLevel{
      tenant_id: TenantContext.get_tenant_id(),
      variant: build(:product_variant),
      on_hand: 0,
      reserved: 0,
      venue_id: nil
    }
  end

  def stock_movement_factory do
    %StockMovement{
      tenant_id: TenantContext.get_tenant_id(),
      variant: build(:product_variant),
      delta: 1,
      kind: :received,
      note: "seed"
    }
  end

  def fulfillment_factory do
    %Fulfillment{
      tenant_id: TenantContext.get_tenant_id(),
      order_line_id: Ecto.UUID.generate(),
      variant: build(:product_variant),
      status: :pending
    }
  end

  def credit_lot_factory do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %CreditLot{
      tenant_id: TenantContext.get_tenant_id(),
      household_id: Ecto.UUID.generate(),
      source: :admin_grant,
      eligible_offering_ids: [],
      quantity_granted: 5,
      remaining: 5,
      granted_at: now
    }
  end

  def credit_ledger_entry_factory do
    %CreditLedgerEntry{
      tenant_id: TenantContext.get_tenant_id(),
      credit_lot: build(:credit_lot),
      household_id: Ecto.UUID.generate(),
      delta: 5,
      reason: :grant
    }
  end

  def cart_factory do
    %Cart{
      tenant_id: TenantContext.get_tenant_id(),
      household_id: Ecto.UUID.generate(),
      discount_code: nil
    }
  end

  def cart_line_factory do
    %CartLine{
      tenant_id: TenantContext.get_tenant_id(),
      cart: build(:cart),
      type: :package,
      ref_id: Ecto.UUID.generate(),
      quantity: 1
    }
  end

  def order_factory do
    seq = sequence(:order_seq, & &1)
    subtotal = 10_000

    %Order{
      tenant_id: TenantContext.get_tenant_id(),
      number: "A-" <> String.pad_leading(Integer.to_string(seq), 6, "0"),
      household_id: Ecto.UUID.generate(),
      status: :pending_payment,
      currency: "CAD",
      subtotal: subtotal,
      discount_total: 0,
      tax_total: 0,
      total: subtotal,
      payment_method: :online,
      refunded_total: 0,
      refunded_refs: []
    }
  end

  def booking_factory do
    %Booking{
      tenant_id: TenantContext.get_tenant_id(),
      session_id: Ecto.UUID.generate(),
      player_id: Ecto.UUID.generate(),
      household_id: Ecto.UUID.generate(),
      status: :confirmed,
      payment_method: :credits,
      credits_used: 1,
      paid_amount: 0,
      currency: "CAD",
      policy_snapshot: SportsCoachBookings.Policies.default_snapshot()
    }
  end

  def booking_event_factory do
    %BookingEvent{
      tenant_id: TenantContext.get_tenant_id(),
      booking: build(:booking),
      kind: "confirmed",
      data: %{}
    }
  end

  def order_line_factory do
    %OrderLine{
      tenant_id: TenantContext.get_tenant_id(),
      order: build(:order),
      type: :package,
      ref_id: Ecto.UUID.generate(),
      description: "Item #{sequence(:order_line_seq, & &1)}",
      unit_price: 5_000,
      quantity: 2,
      discount_amount: 0,
      tax_amount: 0,
      line_total: 10_000,
      refunded_amount: 0,
      taxable: false
    }
  end

  def feedback_skill_tag_factory do
    slug = "skill-#{sequence(:skill_tag_seq, & &1)}"

    %SkillTag{
      tenant_id: TenantContext.get_tenant_id(),
      name: String.replace(slug, "-", " "),
      slug: slug,
      position: 0,
      active: true
    }
  end

  def session_feedback_factory do
    %SessionFeedback{
      tenant_id: TenantContext.get_tenant_id(),
      session_id: Ecto.UUID.generate(),
      player_id: Ecto.UUID.generate(),
      coach_id: Ecto.UUID.generate(),
      body: "Strong session; keep working on the first touch.",
      skill_ratings: %{},
      focus_next: nil,
      visibility: :internal,
      shared_at: nil,
      edited_at: nil
    }
  end

  def feedback_revision_factory do
    %Revision{
      tenant_id: TenantContext.get_tenant_id(),
      feedback: build(:session_feedback),
      revision: 1,
      body: "Previous body",
      skill_ratings: %{},
      visibility: "internal",
      notify: false
    }
  end

  def reservation_factory do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    %Reservation{
      tenant_id: TenantContext.get_tenant_id(),
      token_hash: :crypto.hash(:sha256, token),
      status: :active,
      expires_at: DateTime.add(now, 10, :minute),
      last_activity_at: now
    }
  end

  def reservation_session_factory do
    %ReservationSession{
      tenant_id: TenantContext.get_tenant_id(),
      reservation: build(:reservation),
      session_id: Ecto.UUID.generate()
    }
  end
end
