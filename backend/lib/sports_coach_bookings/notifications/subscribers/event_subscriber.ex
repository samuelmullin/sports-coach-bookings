defmodule SportsCoachBookings.Notifications.Subscribers.EventSubscriber do
  @moduledoc """
  Maps the shared domain-event catalog to branded transactional email. Owned by
  WP-16.

  Each handler resolves the recipients and assigns for its event through other
  contexts' public APIs (never another context's `Repo`), then calls
  `SportsCoachBookings.Notifications.deliver/4`. Delivery is at-least-once, so
  every send is keyed by a stable idempotency key and replayed events are
  no-ops. Lookups that cannot be resolved degrade to `:ok` rather than failing
  the event (see `docs/rfcs/20260928-notifications-event-emails.md`).

  Auth/invite emails (`staff.invited`, `household.member_invited`,
  confirm/reset) are owned by WP-01/WP-02 and are sent directly by their
  notifiers; this subscriber deliberately does not handle them to avoid
  double-emailing.
  """

  @behaviour SportsCoachBookings.Events.Subscriber

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Feedback
  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Ics
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookings.Waivers

  @impl true
  def handle_event("staff.joined", payload), do: staff_change(:staff_joined, payload, "joined")

  def handle_event("staff.removed", payload),
    do: staff_change(:staff_removed, payload, "removed")

  def handle_event("customer.registered", payload), do: customer_registered(payload)

  def handle_event("household.member_joined", payload), do: household_member_joined(payload)

  def handle_event("waiver.published", payload), do: waiver_published(payload)
  def handle_event("waiver.signed", payload), do: waiver_signed(payload)

  def handle_event("order.paid", payload), do: order_paid(payload)
  def handle_event("order.refunded", payload), do: order_refunded(payload)
  def handle_event("order.expired", payload), do: order_expired(payload)

  def handle_event("credits.granted", payload), do: credits_granted(payload)
  def handle_event("credits.expiring_soon", payload), do: credits_expiring(payload)
  def handle_event("credits.expired", payload), do: credits_expired(payload)

  def handle_event("session.cancelled", payload), do: session_cancelled(payload)
  def handle_event("session.rescheduled", payload), do: session_rescheduled(payload)

  def handle_event("booking.created", payload), do: booking_created(payload)
  def handle_event("booking.cancelled", payload), do: booking_cancelled(payload)
  def handle_event("booking.rebooked", payload), do: booking_rebooked(payload)
  def handle_event("booking.attended", payload), do: booking_attended(payload)
  def handle_event("booking.no_show", payload), do: booking_no_show(payload)

  def handle_event("feedback.submitted", payload), do: feedback_submitted(payload)
  def handle_event("stock.low", payload), do: stock_low(payload)

  def handle_event(_name, _payload), do: :ok

  ## Staff

  defp staff_change(template, payload, verb) do
    tenant_id = tenant_id(payload)
    role = payload["role"] || "member"
    member = staff_email(payload["staff_user_id"])

    assigns = %{
      role: role,
      member_email: member,
      event: verb,
      team_url: tenant_url(tenant_id, "/admin/team")
    }

    send_email(
      template,
      admin_recipients(),
      assigns,
      :operational,
      "#{template}:#{payload["membership_id"]}"
    )
  end

  ## Customers

  defp customer_registered(payload) do
    case customer(payload["customer_user_id"]) do
      nil ->
        :ok

      %{email: email, first_name: first_name} ->
        send_email(
          :customer_welcome,
          [customer_recipient(email)],
          %{first_name: first_name || "there", account_url: tenant_url(tenant_id(payload), "/")},
          :transactional,
          "customer_welcome:#{payload["customer_user_id"]}"
        )
    end
  end

  defp household_member_joined(payload) do
    tenant_id = tenant_id(payload)

    send_email(
      :household_member_joined,
      manager_recipients(payload["household_id"]),
      %{
        member_email: customer_email(payload["customer_user_id"]),
        household_url: tenant_url(tenant_id, "/household")
      },
      :operational,
      "household_member_joined:#{payload["member_id"]}"
    )
  end

  ## Waivers

  defp waiver_published(%{"require_resign" => false}), do: :ok

  defp waiver_published(payload) do
    version_id = payload["version_id"]
    tenant_id = tenant_id(payload)

    try do
      Customers.list_households()
      |> Enum.filter(&household_needs_resign?(&1.id, version_id))
      |> Enum.each(fn household ->
        send_email(
          :waiver_resign_required,
          manager_recipients(household.id),
          %{
            waiver_name: waiver_name(payload),
            player_name: nil,
            sign_url: tenant_url(tenant_id, "/waivers")
          },
          :transactional,
          "waiver_resign_required:#{version_id}:#{household.id}"
        )
      end)

      :ok
    rescue
      _ -> :ok
    end
  end

  defp waiver_signed(payload) do
    case player(payload["player_id"]) do
      %{household_id: household_id} ->
        send_email(
          :waiver_signed,
          manager_recipients(household_id),
          %{
            waiver_name: waiver_name(payload),
            player_name: player_name(payload["player_id"]),
            waivers_url: tenant_url(tenant_id(payload), "/waivers")
          },
          :transactional,
          "waiver_signed:#{payload["signature_id"]}"
        )

      _ ->
        :ok
    end
  end

  ## Orders

  defp order_paid(payload) do
    case order(payload["order_id"]) do
      nil ->
        :ok

      order ->
        result =
          send_email(
            :order_receipt,
            manager_recipients(order.household_id),
            order_receipt_assigns(order),
            :transactional,
            "order.paid:#{order.id}:order_receipt"
          )

        confirm_held_bookings(order)
        result
    end
  end

  defp order_refunded(payload) do
    case order(payload["order_id"]) do
      nil ->
        :ok

      order ->
        send_email(
          :order_refunded,
          manager_recipients(order.household_id),
          %{
            order_number: order.number,
            refunded_total: money(order.refunded_total, order.currency),
            reason: nil
          },
          :transactional,
          "order.refunded:#{order.id}:order_refunded"
        )
    end
  end

  defp order_expired(payload) do
    case order(payload["order_id"]) do
      nil ->
        :ok

      order ->
        send_email(
          :order_expired,
          manager_recipients(order.household_id),
          %{order_number: order.number, book_url: tenant_url(tenant_id(payload), "/")},
          :operational,
          "order.expired:#{order.id}:order_expired"
        )
    end
  end

  ## Credits

  defp credits_granted(payload) do
    tenant_id = tenant_id(payload)
    household_id = payload["household_id"]
    lot = credit_lot(payload["lot_id"])

    send_email(
      :credits_granted,
      manager_recipients(household_id),
      %{
        amount: to_string(payload["amount"] || (lot && lot.quantity_granted) || 0),
        balance: balance_string(household_id),
        expires_at: lot && format_date(lot.expires_at),
        book_url: tenant_url(tenant_id, "/")
      },
      :transactional,
      "credits.granted:#{payload["lot_id"]}:credits_granted"
    )
  end

  defp credits_expiring(payload) do
    send_email(
      :credits_expiring,
      manager_recipients(payload["household_id"]),
      %{
        amount: to_string(payload["amount"] || 0),
        expires_at: format_datetime_or_date(payload["expires_at"]),
        book_url: tenant_url(tenant_id(payload), "/")
      },
      :operational,
      "credits.expiring_soon:#{payload["lot_id"]}:credits_expiring"
    )
  end

  defp credits_expired(payload) do
    send_email(
      :credits_expired,
      manager_recipients(payload["household_id"]),
      %{amount: to_string(payload["amount"] || 0), book_url: tenant_url(tenant_id(payload), "/")},
      :operational,
      "credits.expired:#{payload["lot_id"]}:credits_expired"
    )
  end

  ## Sessions

  defp session_cancelled(payload) do
    tenant_id = tenant_id(payload)
    detail = session_detail(payload["session_id"])

    recipients =
      manager_recipients_for_session(payload["session_id"]) ++ coach_recipients(detail)

    send_email(
      :session_cancelled_by_provider,
      recipients,
      %{
        offering_name: offering_name(detail),
        starts_at: format_starts_at(detail, payload["starts_at"]),
        reason: payload["reason"],
        manage_url: tenant_url(tenant_id, "/bookings")
      },
      :operational,
      "session.cancelled:#{payload["session_id"]}:session_cancelled_by_provider"
    )
  end

  defp session_rescheduled(payload) do
    tenant_id = tenant_id(payload)
    detail = session_detail(payload["session_id"])

    recipients =
      manager_recipients_for_session(payload["session_id"]) ++ coach_recipients(detail)

    send_email(
      :session_rescheduled,
      recipients,
      %{
        offering_name: offering_name(detail),
        from_starts_at: format_starts_at(detail, payload["previous_starts_at"]),
        to_starts_at: format_starts_at(detail, payload["starts_at"]),
        venue_name: detail && detail.venue && detail.venue.name,
        manage_url: tenant_url(tenant_id, "/bookings")
      },
      :operational,
      "session.rescheduled:#{payload["session_id"]}:session_rescheduled"
    )
  end

  ## Bookings

  defp booking_created(%{"status" => "confirmed"} = payload),
    do: send_booking_confirmed(payload["booking_id"])

  defp booking_created(_payload), do: :ok

  defp booking_cancelled(payload) do
    booking = booking(payload["booking_id"])
    detail = booking && session_detail(booking.session_id)

    send_email(
      :booking_cancelled,
      manager_recipients(payload["household_id"]),
      %{
        player_name: player_name(payload["player_id"]),
        offering_name: offering_name(detail),
        starts_at: format_starts_at(detail, detail && detail.session.starts_at),
        outcome: cancellation_outcome(payload),
        manage_url: tenant_url(tenant_id(payload), "/bookings")
      },
      :transactional,
      "booking.cancelled:#{payload["booking_id"]}:booking_cancelled"
    )
  end

  defp booking_rebooked(payload) do
    from_detail = session_detail(payload["source_session_id"])
    to_detail = session_detail(payload["session_id"])

    send_email(
      :booking_rebooked,
      manager_recipients(payload["household_id"]),
      %{
        player_name: player_name(payload["player_id"]),
        offering_name: offering_name(to_detail),
        from_starts_at: format_starts_at(from_detail, nil),
        to_starts_at: format_starts_at(to_detail, nil),
        manage_url: tenant_url(tenant_id(payload), "/bookings")
      },
      :operational,
      "booking.rebooked:#{payload["booking_id"]}:booking_rebooked",
      attachments: rebooked_attachments(payload, to_detail)
    )
  end

  defp booking_attended(payload) do
    detail = session_detail(payload["session_id"])

    send_email(
      :booking_attended,
      manager_recipients(payload["household_id"]),
      %{
        player_name: player_name(payload["player_id"]),
        offering_name: offering_name(detail),
        manage_url: tenant_url(tenant_id(payload), "/bookings")
      },
      :transactional,
      "booking.attended:#{payload["booking_id"]}:booking_attended"
    )
  end

  defp booking_no_show(payload) do
    detail = session_detail(payload["session_id"])

    send_email(
      :booking_no_show,
      manager_recipients(payload["household_id"]),
      %{
        player_name: player_name(payload["player_id"]),
        offering_name: offering_name(detail),
        outcome: cancellation_outcome(payload)
      },
      :operational,
      "booking.no_show:#{payload["booking_id"]}:booking_no_show"
    )
  end

  defp send_booking_confirmed(booking_id) do
    with %{} = booking <- booking(booking_id),
         %{} = detail <- session_detail(booking.session_id) do
      send_email(
        :booking_confirmed,
        manager_recipients(booking.household_id),
        booking_confirmed_assigns(booking, detail),
        :transactional,
        "booking_confirmed:#{booking.id}",
        attachments: [ics_attachment(booking, detail, booking.rebook_count || 0)]
      )
    else
      _ -> :ok
    end
  end

  ## Feedback

  defp feedback_submitted(payload) do
    case Feedback.fetch_feedback(payload["feedback_id"]) do
      {:ok, feedback} ->
        send_email(
          :feedback_shared,
          manager_recipients(payload["household_id"]),
          feedback_assigns(feedback, payload),
          :transactional,
          "feedback.submitted:#{feedback.id}:#{payload["updated"] || false}"
        )

      _ ->
        :ok
    end
  end

  ## Inventory

  defp stock_low(payload) do
    variant = fetch(Inventory.fetch_variant(payload["variant_id"]))
    product = variant && fetch(Inventory.fetch_product(variant.product_id))

    send_email(
      :admin_low_stock,
      admin_recipients(),
      %{
        product_name: (product && product.name) || "Product",
        variant_label: variant_label(variant),
        available: to_string(payload["available"] || 0),
        threshold: to_string(payload["threshold"] || 0),
        inventory_url: tenant_url(tenant_id(payload), "/admin/inventory")
      },
      :operational,
      "stock.low:#{payload["variant_id"]}:admin_low_stock"
    )
  end

  ## Assigns builders

  defp booking_confirmed_assigns(booking, detail) do
    %{
      player_name: player_name(booking.player_id),
      offering_name: offering_name(detail),
      starts_at: format_starts_at(detail, detail.session.starts_at),
      venue_name: detail.venue && detail.venue.name,
      venue_address: venue_address(detail.venue),
      map_url: detail.venue && detail.venue.map_url,
      coach_name: detail |> coach_names() |> List.first(),
      booking_reference: booking_reference(booking),
      policy_summary: policy_summary(booking),
      manage_url: tenant_url(booking.tenant_id, "/bookings/#{booking.id}")
    }
  end

  defp order_receipt_assigns(order) do
    %{
      order_number: order.number,
      total: money(order.total, order.currency),
      lines: Enum.map(order.lines, &order_line_label(&1, order.currency)),
      discount_total:
        (order.discount_total > 0 && money(order.discount_total, order.currency)) || nil,
      tax_total: (order.tax_total > 0 && money(order.tax_total, order.currency)) || nil,
      tax_number: nil,
      pickup_note: pickup_note(order),
      order_url: tenant_url(order.tenant_id, "/orders/#{order.id}")
    }
  end

  defp feedback_assigns(feedback, payload) do
    %{
      player_name: player_name(feedback.player_id),
      coach_name: coach_name(feedback.coach_id),
      session_date: session_date(feedback.session_id),
      body: feedback.body,
      ratings: rating_labels(feedback.skill_ratings),
      updated: payload["updated"] == true,
      feedback_url: tenant_url(feedback.tenant_id, "/feedback")
    }
  end

  ## Recipients

  defp manager_recipients(nil), do: []

  defp manager_recipients(household_id) do
    household_id
    |> Customers.list_manager_emails()
    |> Enum.map(&customer_recipient/1)
  end

  defp manager_recipients_for_session(session_id) do
    session_id
    |> households_for_session()
    |> Enum.flat_map(&manager_recipients(&1.id))
  end

  defp admin_recipients do
    Staff.list_team()
    |> Enum.filter(&(&1.role in [:owner, :admin]))
    |> Enum.map(& &1.staff_user)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&staff_recipient/1)
  end

  defp coach_recipients(nil), do: []

  defp coach_recipients(detail) do
    detail.coaches
    |> Enum.map(& &1.staff_user)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&staff_recipient/1)
  end

  defp customer_recipient(email) when is_binary(email),
    do: %{type: :customer_user, id: nil, email: email}

  defp staff_recipient(%{id: id, email: email}),
    do: %{type: :staff_user, id: id, email: email}

  defp households_for_session(session_id) do
    Customers.list_households()
    |> Enum.filter(fn household ->
      household.id
      |> Bookings.list_for_household()
      |> Enum.any?(fn %{booking: booking} -> booking.session_id == session_id end)
    end)
  end

  ## Lookups

  defp booking(id) do
    case Bookings.fetch_booking(id) do
      {:ok, booking} -> booking
      _ -> nil
    end
  end

  defp fetch({:ok, value}), do: value
  defp fetch(_), do: nil

  defp session_detail(id) do
    case Scheduling.session_detail(id) do
      {:ok, detail} -> detail
      _ -> nil
    end
  end

  defp order(id) do
    case Commerce.fetch_order(id) do
      {:ok, order} -> order
      _ -> nil
    end
  end

  defp credit_lot(id) do
    Credits.get_lot!(id)
  rescue
    _ -> nil
  end

  defp customer(id) when is_binary(id), do: Customers.get_customer_user(id)
  defp customer(_), do: nil

  defp customer_email(id), do: id && customer(id) && customer(id).email

  defp player(id) do
    case Players.fetch_player(id) do
      {:ok, player} -> player
      _ -> nil
    end
  end

  defp player_name(id) do
    case player(id) do
      %{preferred_name: name} when is_binary(name) and name != "" -> name
      %{first_name: first, last_name: last} -> join_name(first, last)
      _ -> "Player"
    end
  end

  defp staff_email(id) do
    case Staff.get_staff_user(id) do
      %{email: email} -> email
      _ -> nil
    end
  end

  defp waiver_name(payload) do
    case payload["template_id"] do
      nil ->
        "waiver"

      template_id ->
        try do
          Waivers.get_template!(template_id).name
        rescue
          _ -> "waiver"
        end
    end
  end

  defp coach_name(nil), do: "Your coach"

  defp coach_name(membership_id) do
    case Staff.get_membership!(membership_id) do
      %{display_name: name} when is_binary(name) and name != "" -> name
      %{staff_user_id: staff_user_id} -> staff_email(staff_user_id) || "Your coach"
    end
  rescue
    _ -> "Your coach"
  end

  defp coach_names(detail) do
    coaches = Map.get(detail, :coaches) || []

    Enum.map(coaches, fn membership ->
      membership.display_name || (membership.staff_user && membership.staff_user.email) || "Coach"
    end)
  end

  defp offering_name(nil), do: "Session"
  defp offering_name(%{offering: %{name: name}}) when is_binary(name), do: name
  defp offering_name(_), do: "Session"

  defp booking_reference(%{id: id}), do: String.slice(id, 0, 8) |> String.upcase()

  defp policy_summary(%{policy_snapshot: snapshot}) when is_map(snapshot) do
    snapshot["summary"] || snapshot[:summary]
  end

  defp policy_summary(_), do: nil

  defp cancellation_outcome(payload) do
    cond do
      payload["credit_outcome"] -> "Credits: #{payload["credit_outcome"]}"
      payload["refund_amount"] -> "Refund: #{payload["refund_amount"]}"
      true -> "No credits or refund are due under the policy in effect."
    end
  end

  defp venue_address(nil), do: nil

  defp venue_address(venue) do
    [venue.address_line1, venue.city, venue.province, venue.postal_code]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
    |> case do
      "" -> nil
      address -> address
    end
  end

  defp order_line_label(line, currency) do
    "#{line.description} x#{line.quantity} - #{money(line.line_total, currency)}"
  end

  defp pickup_note(%{lines: lines}) do
    if Enum.any?(lines, &(&1.type == :product)) do
      "We will email you when your items are ready for pickup."
    end
  end

  defp rating_labels(ratings) when is_map(ratings) and map_size(ratings) > 0 do
    Enum.map(ratings, fn {label, value} -> "#{humanize(label)}: #{value}/5" end)
  end

  defp rating_labels(_), do: []

  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp variant_label(nil), do: nil

  defp variant_label(%{option_values: values}) when is_map(values) and map_size(values) > 0 do
    Enum.map_join(values, ", ", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp variant_label(_), do: nil

  defp household_needs_resign?(household_id, version_id) do
    status = Waivers.status_for_household(household_id)
    players = status[:players] || status.players || []

    Enum.any?(players, fn player ->
      waivers = player[:waivers] || player.waivers || []

      Enum.any?(waivers, fn waiver ->
        waiver[:version_id] == version_id and not waiver[:signed]
      end)
    end)
  rescue
    _ -> false
  end

  defp balance_string(household_id) do
    household_id
    |> Credits.balance()
    |> Enum.map(& &1.amount)
    |> Enum.sum()
    |> to_string()
  rescue
    _ -> nil
  end

  defp session_date(nil), do: nil

  defp session_date(session_id) do
    case session_detail(session_id) do
      %{session: session} -> format_date(session.starts_at)
      _ -> nil
    end
  end

  ## Time / money formatting

  defp format_starts_at(_detail, nil), do: nil

  defp format_starts_at(detail, %DateTime{} = starts_at),
    do: format_datetime(starts_at, venue_timezone(detail))

  defp format_starts_at(detail, starts_at) when is_binary(starts_at) do
    case DateTime.from_iso8601(starts_at) do
      {:ok, datetime, _offset} -> format_datetime(datetime, venue_timezone(detail))
      _ -> starts_at
    end
  end

  defp venue_timezone(%{venue: %{timezone: timezone}}) when is_binary(timezone), do: timezone
  defp venue_timezone(_), do: "Etc/UTC"

  defp format_datetime(%DateTime{} = datetime, timezone) do
    shifted =
      case DateTime.shift_zone(datetime, timezone) do
        {:ok, zoned} -> zoned
        {:error, _} -> datetime
      end

    Calendar.strftime(shifted, "%a, %d %b %Y at %I:%M %p")
  end

  defp format_date(nil), do: nil
  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%d %b %Y")
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")

  defp format_datetime_or_date(nil), do: nil

  defp format_datetime_or_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_date(datetime)
      _ -> value
    end
  end

  defp format_datetime_or_date(value), do: format_date(value)

  defp money(amount, currency) when is_integer(amount) and is_binary(currency),
    do: amount |> Money.new(currency) |> Money.to_string()

  defp money(_, _), do: nil

  ## Calendar attachments

  defp ics_attachment(booking, detail, sequence) do
    ics =
      Ics.for_booking(%{
        uid: booking.id,
        sequence: sequence,
        starts_at: detail.session.starts_at,
        ends_at: detail.session.ends_at,
        timezone: venue_timezone(detail),
        summary: offering_name(detail),
        location: (detail.venue && detail.venue.name) || "",
        description: policy_summary(booking) || ""
      })

    %{
      filename: "booking.ics",
      content_type: "text/calendar; charset=utf-8; method=PUBLISH",
      content: ics
    }
  end

  defp rebooked_attachments(payload, to_detail) do
    case booking(payload["booking_id"]) do
      %{} = booking ->
        [ics_attachment(booking, to_detail, (booking.rebook_count || 0) + 1)]

      _ ->
        []
    end
  end

  defp confirm_held_bookings(%{lines: lines}) do
    lines
    |> Enum.filter(&(&1.type == :drop_in and is_binary(&1.booking_id)))
    |> Enum.each(&send_booking_confirmed(&1.booking_id))
  end

  ## Dispatch

  defp send_email(template, recipients, assigns, category, idempotency_key, opts \\ []) do
    recipients = Enum.uniq_by(recipients, & &1.email)

    if recipients == [] do
      :ok
    else
      case Notifications.deliver(template, recipients, assigns,
             category: category,
             idempotency_key: idempotency_key,
             attachments: Keyword.get(opts, :attachments, [])
           ) do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  ## URLs

  defp tenant_url(nil, path), do: app_url() <> path

  defp tenant_url(tenant_id, path) do
    case Tenancy.get_tenant(tenant_id) do
      %{slug: slug} -> "#{scheme()}://#{slug}.#{base_domain()}#{path}"
      _ -> app_url() <> path
    end
  end

  defp app_url do
    Application.get_env(
      :sports_coach_bookings,
      :notifications_app_url,
      "https://sportscoachbookings.com"
    )
  end

  defp scheme, do: Application.get_env(:sports_coach_bookings, :notifications_url_scheme, "https")

  defp base_domain,
    do: Application.get_env(:sports_coach_bookings, :base_domain, "sportscoachbookings.com")

  defp tenant_id(payload), do: payload["tenant_id"] || TenantContext.get_tenant_id()

  defp join_name(nil, nil), do: "Player"
  defp join_name(first, nil), do: first
  defp join_name(nil, last), do: last
  defp join_name(first, last), do: "#{first} #{last}"
end
