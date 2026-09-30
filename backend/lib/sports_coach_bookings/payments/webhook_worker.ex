defmodule SportsCoachBookings.Payments.WebhookWorker do
  @moduledoc """
  Applies a recorded provider webhook event to the Payments context.

  Runs with tenant context restored by `SportsCoachBookings.Core.TenantWorker`
  (the tenant was resolved from the payload/account at ingest time). The event
  is replayed safely:

    * the `payments_webhook_events` row is deduped on `(provider, event_id)` at
      ingest, so a replayed webhook enqueues at most one job;
    * each status transition is a guarded `UPDATE ... WHERE status <> target`, so
      even concurrent jobs publish `payment.succeeded` / `payment.failed` only
      once (invariant 6);
    * a refund is keyed by unique `(tenant_id, refund_ref)`, so `charge.refunded`
      reconciles to a single refund row and publishes `payment.refunded` once.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :payments, max_attempts: 5

  import Ecto.Query

  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Payments.Payment
  alias SportsCoachBookings.Payments.ProviderAccount
  alias SportsCoachBookings.Payments.Refund
  alias SportsCoachBookings.Payments.WebhookEvent
  alias SportsCoachBookings.Repo

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: args}) do
    case load_event(args["webhook_event_id"]) do
      nil -> {:discard, :event_not_found}
      event -> run(event, args)
    end
  end

  defp run(event, args) do
    case Repo.with_tenant_tx(fn -> apply_event(args) end) do
      {:ok, :ok} ->
        mark_done(event)
        :ok

      {:ok, {:discard, reason}} ->
        mark_done(event)
        {:discard, reason}

      {:ok, {:error, reason}} ->
        mark_error(event, reason)
        {:error, reason}

      {:error, reason} ->
        mark_error(event, reason)
        {:error, reason}
    end
  end

  defp apply_event(%{"type" => type} = args) do
    dispatch(type, args["data"] || %{})
  end

  defp apply_event(_args), do: {:discard, :invalid_args}

  defp dispatch("checkout_completed", data), do: handle_checkout_completed(data)
  defp dispatch("checkout_expired", data), do: handle_checkout_expired(data)
  defp dispatch("payment_failed", data), do: handle_payment_failed(data)
  defp dispatch("charge_refunded", data), do: handle_charge_refunded(data)
  defp dispatch("account_updated", data), do: handle_account_updated(data)
  defp dispatch(_type, _data), do: {:discard, :unhandled_type}

  ## checkout.session.completed

  defp handle_checkout_completed(data) do
    case find_payment(data) do
      nil -> {:discard, :payment_not_found}
      payment -> mark_succeeded(payment, data)
    end
  end

  defp mark_succeeded(payment, data) do
    {count, _} =
      Repo.update_all(
        from(p in Payment, where: p.id == ^payment.id and p.status != :succeeded),
        set: [
          status: :succeeded,
          payment_ref: data["payment_ref"],
          raw: data,
          updated_at: now()
        ]
      )

    if count > 0 do
      publish("payment.succeeded", payment, amount(data, payment), currency(data))
    end

    :ok
  end

  ## checkout.session.expired

  defp handle_checkout_expired(data) do
    case find_payment(data) do
      nil ->
        {:discard, :payment_not_found}

      payment ->
        Repo.update_all(
          from(p in Payment, where: p.id == ^payment.id and p.status == :pending),
          set: [status: :expired, raw: data, updated_at: now()]
        )

        :ok
    end
  end

  ## payment_intent.payment_failed

  defp handle_payment_failed(data) do
    case find_payment(data) do
      nil ->
        {:discard, :payment_not_found}

      payment ->
        {count, _} =
          Repo.update_all(
            from(p in Payment, where: p.id == ^payment.id and p.status == :pending),
            set: [status: :failed, payment_ref: data["payment_ref"], raw: data, updated_at: now()]
          )

        if count > 0 do
          publish("payment.failed", payment, amount(data, payment), currency(data))
        end

        :ok
    end
  end

  ## charge.refunded

  defp handle_charge_refunded(data) do
    payment = find_payment(data)
    refund_ref = data["refund_ref"]

    cond do
      is_nil(payment) -> {:discard, :payment_not_found}
      not is_binary(refund_ref) or refund_ref == "" -> {:discard, :missing_refund_ref}
      true -> reconcile_refund(payment, data, refund_ref)
    end
  end

  defp reconcile_refund(payment, data, refund_ref) do
    refunded = data["refund_amount"] || data["amount"] || 0

    case Repo.get_by(Refund, tenant_id: payment.tenant_id, refund_ref: refund_ref) do
      %Refund{status: :succeeded} ->
        :ok

      %Refund{} = refund ->
        transition_refund(refund, payment, refunded, data)

      nil ->
        insert_reconciled_refund(payment, refunded, refund_ref, data)
    end
  end

  defp transition_refund(refund, payment, refunded, data) do
    {count, _} =
      Repo.update_all(
        from(r in Refund, where: r.id == ^refund.id and r.status != :succeeded),
        set: [status: :succeeded, updated_at: now()]
      )

    if count > 0 do
      publish("payment.refunded", payment, refunded, currency(data))
    end

    :ok
  end

  defp insert_reconciled_refund(payment, refunded, refund_ref, data) do
    changeset =
      Refund.changeset(%Refund{}, %{
        tenant_id: payment.tenant_id,
        payment_id: payment.id,
        amount: refunded,
        reason: "provider",
        refund_ref: refund_ref,
        status: :succeeded
      })

    case Repo.insert(changeset) do
      {:ok, _refund} ->
        publish("payment.refunded", payment, refunded, currency(data))
        :ok

      {:error, %Ecto.Changeset{}} ->
        # Raced with another job or an explicit refund: already reconciled.
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## account.updated

  defp handle_account_updated(data) do
    account_ref = data["account_ref"]

    case account_ref && Repo.get_by(ProviderAccount, account_ref: account_ref) do
      nil ->
        {:discard, :account_not_found}

      account ->
        attrs = %{
          status: account_status(data),
          charges_enabled: data["charges_enabled"] == true,
          payouts_enabled: data["payouts_enabled"] == true,
          requirements: requirements(data["requirements"])
        }

        case Repo.update(ProviderAccount.changeset(account, attrs)) do
          {:ok, _account} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  ## Shared helpers

  defp find_payment(data) do
    by_checkout(data["checkout_ref"]) || by_payment_ref(data["payment_ref"])
  end

  defp by_checkout(nil), do: nil
  defp by_checkout(ref), do: Repo.get_by(Payment, checkout_ref: ref)

  defp by_payment_ref(nil), do: nil
  defp by_payment_ref(ref), do: Repo.get_by(Payment, payment_ref: ref)

  defp publish(name, payment, amount, currency) do
    {:ok, _job} =
      Events.publish(name, %{
        tenant_id: payment.tenant_id,
        payment_id: payment.id,
        order_id: payment.order_id,
        amount: amount,
        currency: currency
      })
  end

  defp amount(data, payment), do: data["amount"] || payment.amount
  defp currency(data), do: data["currency"]

  defp account_status(data) do
    cond do
      data["charges_enabled"] == true -> "enabled"
      data["requirements"] not in [nil, [], %{}] -> "restricted"
      true -> "pending"
    end
  end

  defp requirements(nil), do: %{}
  defp requirements(requirements) when is_map(requirements), do: requirements
  defp requirements(requirements) when is_list(requirements), do: %{"due" => requirements}
  defp requirements(_requirements), do: %{}

  defp load_event(nil), do: nil
  defp load_event(id), do: Repo.get(WebhookEvent, id, skip_tenant: true)

  defp mark_done(event) do
    event
    |> WebhookEvent.changeset(%{processed_at: now(), error: nil})
    |> Repo.update(skip_tenant: true)
  end

  defp mark_error(event, reason) do
    event
    |> WebhookEvent.changeset(%{error: inspect(reason)})
    |> Repo.update(skip_tenant: true)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
