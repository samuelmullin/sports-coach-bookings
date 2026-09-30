defmodule SportsCoachBookings.Payments do
  @moduledoc """
  Payment provider abstraction and Stripe Connect. Owned by WP-04.

  The context is provider-agnostic: all provider calls go through the module
  configured at `config :sports_coach_bookings, :payments_provider` (tests use
  `Payments.Providers.Fake`). See `Payments.Provider` for the behaviour and
  `Payments.Providers.Stripe` for the first implementation.

  Everything tenant-owned is written inside `Repo.with_tenant_tx/2`, so RLS
  applies. Webhooks are recorded in the platform-level `payments_webhook_events`
  table (deduped on `(provider, event_id)`) and processed in an Oban
  `Payments.WebhookWorker`.

  ## Public API

      Payments.connect_status()                        # => status map
      Payments.start_onboarding(return_url)            # => {:ok, url} | {:error, term}
      Payments.create_checkout(order)                  # => {:ok, redirect_url} | {:error, term}
      Payments.refund(payment_id, money, reason, actor) # => {:ok, refund} | {:error, term}

  `create_checkout/1` returns `{:error, :provider_not_ready}` when the tenant
  has not connected a provider account or its `charges_enabled` is false.
  """

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Payments.CheckoutRequest
  alias SportsCoachBookings.Payments.CheckoutRequest.LineItem
  alias SportsCoachBookings.Payments.CheckoutSession
  alias SportsCoachBookings.Payments.NormalizedEvent
  alias SportsCoachBookings.Payments.Payment
  alias SportsCoachBookings.Payments.ProviderAccount
  alias SportsCoachBookings.Payments.Refund
  alias SportsCoachBookings.Payments.WebhookEvent
  alias SportsCoachBookings.Payments.WebhookWorker
  alias SportsCoachBookings.Repo

  @default_platform_fee_bps 0

  @typedoc "Serialisable provider-connection status for the staff UI."
  @type connect_status :: %{
          provider: String.t(),
          account_ref: String.t() | nil,
          status: String.t(),
          charges_enabled: boolean(),
          payouts_enabled: boolean(),
          requirements: map(),
          platform_fee_bps: non_neg_integer()
        }

  ## Connection status

  @doc """
  Returns the resolved tenant's provider-connection status.

  When the tenant has an account, the status is refreshed from the provider and
  persisted before being returned; if the provider call fails the last persisted
  status is returned. A tenant with no account is reported as `not_connected`
  with `charges_enabled: false`.
  """
  @spec connect_status() :: connect_status()
  def connect_status do
    case fetch_account() do
      %ProviderAccount{} = account -> refresh_account(account)
      _ -> disconnected_status()
    end
  end

  @doc """
  Starts (or resumes) provider onboarding for the resolved tenant.

  Creates the connected account on first use, then returns a hosted onboarding
  URL. `return_url` is where the provider returns after onboarding;
  `:refresh_url` (defaults to `return_url`) is used when the link expires.
  """
  @spec start_onboarding(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_onboarding(return_url, opts \\ []) when is_binary(return_url) do
    tenant = TenantContext.get_tenant!()
    refresh_url = Keyword.get(opts, :refresh_url, return_url)
    actor = Keyword.get(opts, :actor)

    with {:ok, account} <- ensure_account(tenant, actor) do
      provider().onboarding_link(account.account_ref, return_url, refresh_url)
    end
  end

  ## Checkout

  @doc """
  Creates a hosted checkout session for `order` on the tenant's connected
  account and returns the provider redirect URL.

  `order` may be a struct or a map (string or atom keys) with at least `id`,
  `currency`, `line_items` (each `%{name, unit_amount, quantity}`), and
  optionally `number`, `customer_email`, `success_url`, `cancel_url`.

  Returns `{:error, :provider_not_ready}` when the tenant has no connected
  account or `charges_enabled` is false.
  """
  @spec create_checkout(term()) :: {:ok, String.t()} | {:error, term()}
  def create_checkout(order) do
    tenant = TenantContext.get_tenant!()

    case fetch_account() do
      %ProviderAccount{charges_enabled: true} = account ->
        do_create_checkout(tenant, account, order)

      _ ->
        {:error, :provider_not_ready}
    end
  end

  ## Refunds

  @doc """
  Refunds `money` of `payment` at the provider and records a `refunds` row.

  Auditable: writes an audit entry and publishes `payment.refunded` inside the
  same transaction as the refund row.
  """
  @spec refund(binary(), Money.t(), term(), term()) ::
          {:ok, Refund.t()} | {:error, term()}
  def refund(payment_id, %Money{} = money, reason, actor) do
    with {:ok, payment} <- fetch_payment(payment_id),
         {:ok, account} <- ready_account(),
         {:ok, refund_ref} <-
           provider().refund(account.account_ref, payment.payment_ref, money, reason) do
      persist_refund(payment, money, reason, refund_ref, actor)
    end
  end

  @doc "Fetches a payment for the resolved tenant, or `nil`."
  @spec get_payment(binary()) :: Payment.t() | nil
  def get_payment(id) do
    case read(fn -> Repo.get(Payment, id) end) do
      %Payment{} = payment -> payment
      _ -> nil
    end
  end

  @doc "Lists the resolved tenant's refunds for a payment, newest first."
  @spec list_refunds(binary()) :: [Refund.t()]
  def list_refunds(payment_id) do
    read(fn ->
      Repo.all(
        from r in Refund,
          where: r.payment_id == ^payment_id,
          order_by: [desc: r.inserted_at]
      )
    end)
  end

  ## Webhooks

  @doc """
  Verifies, records, and enqueues a provider webhook.

  Returns `{:ok, :received}`, `{:ok, :duplicate}` (the event was already
  recorded), or `{:error, :invalid_signature}`. The event is deduped on
  `(provider, event_id)`; processing happens in `Payments.WebhookWorker`.
  """
  @spec ingest_webhook(atom() | String.t(), binary(), list() | map()) ::
          {:ok, :received | :duplicate} | {:error, :invalid_signature}
  def ingest_webhook(provider_name, raw_body, headers) do
    provider_name = to_string(provider_name)
    provider_module = provider()

    with {:ok, raw_event} <- provider_module.verify_webhook(raw_body, headers) do
      case provider_module.normalize_event(raw_event) do
        {:ok, %NormalizedEvent{} = normalized} ->
          record_and_enqueue(provider_name, normalized, raw_event)

        :ignore ->
          record_ignored(provider_name, raw_event)
      end
    end
  end

  ## Internals: accounts

  defp fetch_account do
    case read(fn ->
           Repo.one(from a in ProviderAccount, order_by: [asc: a.inserted_at], limit: 1)
         end) do
      %ProviderAccount{} = account -> account
      _ -> nil
    end
  end

  defp ensure_account(tenant, actor) do
    case fetch_account() do
      %ProviderAccount{} = account ->
        {:ok, account}

      _ ->
        case provider().create_connected_account(tenant) do
          {:ok, account_ref} -> insert_account(tenant, account_ref, actor)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp insert_account(tenant, account_ref, actor) do
    changeset =
      ProviderAccount.changeset(%ProviderAccount{}, %{
        tenant_id: tenant.id,
        provider: provider_name(),
        account_ref: account_ref,
        status: "pending",
        platform_fee_bps: default_fee_bps()
      })

    result =
      Repo.with_tenant_tx(fn ->
        case Repo.insert(changeset) do
          {:ok, account} ->
            {:ok, _audit} =
              Audit.record(actor, "payments.account.connected", account, %{
                provider: account.provider,
                account_ref: account.account_ref
              })

            account

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, account} -> {:ok, account}
      {:error, reason} -> {:error, reason}
    end
  end

  defp refresh_account(account) do
    case provider().account_status(account.account_ref) do
      {:ok, status} -> persist_status(account, status)
      {:error, _reason} -> serialize_account(account)
    end
  end

  defp persist_status(account, status) do
    attrs = %{
      status: derive_status(status),
      charges_enabled: Map.get(status, :charges_enabled, false) == true,
      payouts_enabled: Map.get(status, :payouts_enabled, false) == true,
      requirements: normalize_requirements(Map.get(status, :requirements_due))
    }

    case update_in_tx(ProviderAccount.changeset(account, attrs)) do
      {:ok, updated} -> serialize_account(updated)
      {:error, _reason} -> serialize_account(account)
    end
  end

  defp derive_status(status) do
    cond do
      Map.get(status, :charges_enabled) == true -> "enabled"
      Map.get(status, :requirements_due) not in [nil, [], %{}] -> "restricted"
      true -> "pending"
    end
  end

  defp normalize_requirements(nil), do: %{}
  defp normalize_requirements(due) when is_list(due), do: %{"due" => due}
  defp normalize_requirements(due) when is_map(due), do: due
  defp normalize_requirements(_due), do: %{}

  defp disconnected_status do
    %{
      provider: provider_name(),
      account_ref: nil,
      status: "not_connected",
      charges_enabled: false,
      payouts_enabled: false,
      requirements: %{},
      platform_fee_bps: default_fee_bps()
    }
  end

  defp serialize_account(account) do
    %{
      provider: account.provider,
      account_ref: account.account_ref,
      status: account.status,
      charges_enabled: account.charges_enabled,
      payouts_enabled: account.payouts_enabled,
      requirements: account.requirements,
      platform_fee_bps: account.platform_fee_bps
    }
  end

  ## Internals: checkout

  defp do_create_checkout(tenant, account, order) do
    request = build_request(tenant, account, order)

    case provider().create_checkout(account.account_ref, request) do
      {:ok, %CheckoutSession{} = session} ->
        case insert_pending_payment(tenant, request, session) do
          {:ok, _payment} -> {:ok, session.redirect_url}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request(tenant, account, order) do
    currency = get(order, :currency) || tenant.currency
    line_items = build_line_items(order, currency)
    total = Enum.reduce(line_items, 0, fn item, acc -> acc + item.unit_amount * item.quantity end)
    fee = Money.apply_bps(Money.new(total, currency), account.platform_fee_bps)

    %CheckoutRequest{
      order_id: get(order, :id),
      order_number: to_string(get(order, :number) || get(order, :order_number) || "ORDER"),
      customer_email: get(order, :customer_email) || get(order, :email),
      line_items: line_items,
      currency: currency,
      application_fee_amount: fee.amount,
      success_url: get(order, :success_url) || default_url(:payments_checkout_success_url),
      cancel_url: get(order, :cancel_url) || default_url(:payments_checkout_cancel_url),
      metadata: %{
        "tenant_id" => tenant.id,
        "order_id" => get(order, :id),
        "order_number" => to_string(get(order, :number) || "ORDER")
      }
    }
  end

  defp build_line_items(order, currency) do
    case get(order, :line_items) do
      items when is_list(items) and items != [] ->
        Enum.map(items, &build_line_item(&1, currency))

      _ ->
        total = get(order, :total) || 0

        [
          %LineItem{
            name: to_string(get(order, :number) || "Order"),
            unit_amount: total,
            quantity: 1
          }
        ]
    end
  end

  defp build_line_item(item, currency) do
    %LineItem{
      name: to_string(get(item, :name) || get(item, :description) || "Item"),
      unit_amount: get(item, :unit_amount) || get(item, :price) || 0,
      quantity: get(item, :quantity) || 1,
      metadata: %{"currency" => currency}
    }
  end

  defp insert_pending_payment(tenant, request, session) do
    changeset =
      Payment.changeset(%Payment{}, %{
        tenant_id: tenant.id,
        provider: provider_name(),
        order_id: request.order_id,
        checkout_ref: session.session_ref,
        amount: total_amount(request),
        status: :pending,
        raw: %{}
      })

    insert_in_tx(changeset)
  end

  defp total_amount(%CheckoutRequest{line_items: line_items}) do
    Enum.reduce(line_items, 0, fn item, acc -> acc + item.unit_amount * item.quantity end)
  end

  ## Internals: refunds

  defp ready_account do
    case fetch_account() do
      %ProviderAccount{} = account -> {:ok, account}
      _ -> {:error, :provider_not_ready}
    end
  end

  defp fetch_payment(id) do
    case read(fn -> Repo.get(Payment, id) end) do
      %Payment{payment_ref: nil} -> {:error, :not_refundable}
      %Payment{} = payment -> {:ok, payment}
      _ -> {:error, :not_found}
    end
  end

  defp persist_refund(payment, money, reason, refund_ref, actor) do
    changeset =
      Refund.changeset(%Refund{}, %{
        tenant_id: payment.tenant_id,
        payment_id: payment.id,
        amount: money.amount,
        reason: to_string(reason),
        refund_ref: refund_ref,
        status: :succeeded,
        actor_type: actor_type(actor),
        actor_id: actor_id(actor)
      })

    result =
      Repo.with_tenant_tx(fn ->
        case Repo.insert(changeset) do
          {:ok, refund} ->
            {:ok, _audit} =
              Audit.record(actor, "payments.refund", refund, %{
                payment_id: payment.id,
                amount: money.amount,
                currency: money.currency,
                refund_ref: refund_ref
              })

            {:ok, _event} =
              Events.publish("payment.refunded", %{
                tenant_id: payment.tenant_id,
                payment_id: payment.id,
                order_id: payment.order_id,
                amount: money.amount,
                currency: money.currency,
                refund_id: refund.id,
                refund_ref: refund_ref
              })

            refund

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, %Refund{} = refund} -> {:ok, refund}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Internals: webhook ingest

  defp record_and_enqueue(provider_name, %NormalizedEvent{} = normalized, raw_event) do
    attrs = %{
      provider: provider_name,
      event_id: normalized.event_id,
      type: to_string(normalized.type),
      payload: raw_event
    }

    case insert_webhook_event(attrs) do
      {:ok, :duplicate} ->
        {:ok, :duplicate}

      {:ok, event} ->
        tenant_id = resolve_tenant_id(normalized.data)

        if is_binary(tenant_id) do
          enqueue_webhook(event, provider_name, normalized, tenant_id)
        end

        {:ok, :received}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_ignored(provider_name, raw_event) do
    attrs = %{
      provider: provider_name,
      event_id: raw_event["id"] || Ecto.UUID.generate(),
      type: raw_event["type"] || "unknown",
      payload: raw_event,
      processed_at: now()
    }

    case insert_webhook_event(attrs) do
      {:ok, :duplicate} -> {:ok, :duplicate}
      {:ok, _event} -> {:ok, :received}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_webhook_event(attrs) do
    query =
      from e in WebhookEvent,
        where: e.provider == ^attrs.provider and e.event_id == ^attrs.event_id

    case Repo.one(query, skip_tenant: true) do
      %WebhookEvent{processed_at: nil} = event ->
        {:ok, event}

      %WebhookEvent{} ->
        {:ok, :duplicate}

      nil ->
        # Platform-level table: no tenant context exists at insert time; the
        # tenant is resolved from the payload/account afterwards.
        case Repo.insert(WebhookEvent.changeset(%WebhookEvent{}, attrs), skip_tenant: true) do
          {:ok, event} -> {:ok, event}
          {:error, changeset} -> duplicate_or_error(attrs, changeset)
        end
    end
  end

  defp duplicate_or_error(attrs, changeset) do
    if changeset.errors[:event_id] || changeset.errors[:provider] do
      case Repo.one(
             from(e in WebhookEvent,
               where: e.provider == ^attrs.provider and e.event_id == ^attrs.event_id
             ),
             skip_tenant: true
           ) do
        %WebhookEvent{processed_at: nil} = event -> {:ok, event}
        %WebhookEvent{} -> {:ok, :duplicate}
        nil -> {:error, :duplicate}
      end
    else
      {:error, changeset}
    end
  end

  defp enqueue_webhook(event, provider_name, normalized, tenant_id) do
    args = %{
      "tenant_id" => tenant_id,
      "provider" => provider_name,
      "type" => to_string(normalized.type),
      "data" => json_safe(normalized.data),
      "webhook_event_id" => event.id
    }

    args
    |> WebhookWorker.new()
    |> Oban.insert()
  end

  defp resolve_tenant_id(data) when is_map(data) do
    data["tenant_id"] ||
      get_in(data, ["metadata", "tenant_id"]) ||
      get_in(data, ["object", "metadata", "tenant_id"])
  end

  defp resolve_tenant_id(_data), do: nil

  ## Internals: plumbing

  defp provider,
    do: Application.get_env(:sports_coach_bookings, :payments_provider, Providers.Fake)

  defp provider_name do
    provider() |> Module.split() |> List.last() |> Macro.underscore()
  end

  defp default_fee_bps do
    Application.get_env(
      :sports_coach_bookings,
      :payments_default_platform_fee_bps,
      @default_platform_fee_bps
    )
  end

  defp default_url(key) do
    Application.get_env(
      :sports_coach_bookings,
      key,
      "https://sportscoachbookings.com/portal/checkout"
    )
  end

  defp get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get(_other, _key), do: nil

  defp actor_type(nil), do: nil
  defp actor_type(%StaffActor{}), do: "StaffActor"
  defp actor_type(%CustomerActor{}), do: "CustomerActor"
  defp actor_type(_actor), do: nil

  defp actor_id(%StaffActor{staff_user_id: id}), do: id
  defp actor_id(%CustomerActor{customer_user_id: id}), do: id
  defp actor_id(_actor), do: nil

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_in_tx(changeset) do
    Repo.with_tenant_tx(fn ->
      case Repo.insert(changeset) do
        {:ok, record} -> record
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp update_in_tx(changeset) do
    Repo.with_tenant_tx(fn ->
      case Repo.update(changeset) do
        {:ok, record} -> record
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  @doc false
  @spec json_safe(term()) :: term()
  def json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def json_safe(%Date{} = value), do: Date.to_iso8601(value)
  def json_safe(%Time{} = value), do: Time.to_iso8601(value)

  def json_safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_safe(v)} end)

  def json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  def json_safe(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  def json_safe(value), do: value
end
