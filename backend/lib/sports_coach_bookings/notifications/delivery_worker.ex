defmodule SportsCoachBookings.Notifications.DeliveryWorker do
  @moduledoc """
  Sends one delivery from a message. Runs with tenant context restored by
  `SportsCoachBookings.Core.TenantWorker`.

  On failure the job is retried with exponential backoff up to
  `max_attempts`; on the final failed attempt the delivery is marked `failed`
  and the job is discarded.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :notifications, max_attempts: 5

  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Deliverer
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.DeliveryRef
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Notifications.Templates
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Tenancy

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: args} = job) do
    case Repo.with_tenant_tx(fn -> attempt(job, args) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    min(3600, trunc(:math.pow(attempt, 4) + 15))
  end

  defp attempt(job, args) do
    case Repo.get(Delivery, args["delivery_id"]) do
      nil ->
        {:discard, :delivery_not_found}

      %Delivery{status: status} when status in [:delivered, :suppressed] ->
        {:discard, :already_terminal}

      %Delivery{} = delivery ->
        message = Repo.get!(Message, delivery.message_id)

        case deliver(delivery, message, args) do
          {:ok, response} -> mark_sent(delivery, response)
          {:error, {:unknown_template, _} = reason} -> {:discard, reason}
          {:error, reason} -> handle_failure(job, delivery, reason)
        end
    end
  end

  defp deliver(delivery, message, args) do
    tenant_id = delivery.tenant_id

    with {:ok, _template} <- fetch_template(message.template_key),
         {:ok, rendered} <-
           Notifications.render(message.template_key, message.assigns,
             tenant_id: tenant_id,
             category: message.category
           ) do
      delivery
      |> build_email(message, args, rendered)
      |> Deliverer.deliver()
    end
  end

  defp fetch_template(template_key) do
    case Templates.get(template_key) do
      nil -> {:error, {:unknown_template, template_key}}
      module -> {:ok, module}
    end
  end

  defp build_email(delivery, message, args, rendered) do
    tenant = Tenancy.get_tenant!(delivery.tenant_id)
    show_unsubscribe = message.category in [:operational, :marketing]
    unsubscribe_url = unsubscribe_url(delivery, show_unsubscribe)

    Swoosh.Email.new()
    |> Swoosh.Email.from({tenant.name, Notifications.from_address()})
    |> put_reply_to(tenant.contact_email)
    |> Swoosh.Email.to(delivery.email)
    |> Swoosh.Email.subject(rendered.subject)
    |> Swoosh.Email.html_body(rendered.html)
    |> Swoosh.Email.text_body(rendered.text)
    |> put_unsubscribe_headers(unsubscribe_url)
    |> put_attachments(args["attachments"])
    |> put_provider_options(message, delivery)
  end

  defp unsubscribe_url(_delivery, false), do: nil

  defp unsubscribe_url(delivery, true) do
    Notifications.unsubscribe_url(%{
      tenant_id: delivery.tenant_id,
      subject_type: subject_type(delivery.recipient_type),
      subject_id: delivery.recipient_id,
      email: delivery.email
    })
  end

  defp put_reply_to(email, nil), do: email
  defp put_reply_to(email, reply_to), do: Swoosh.Email.reply_to(email, reply_to)

  defp put_unsubscribe_headers(email, nil), do: email

  defp put_unsubscribe_headers(email, url) do
    email
    |> Swoosh.Email.header("List-Unsubscribe", "<#{url}>")
    |> Swoosh.Email.header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
  end

  defp put_attachments(email, nil), do: email

  defp put_attachments(email, attachments) when is_list(attachments) do
    Enum.reduce(attachments, email, fn attachment, acc ->
      case build_attachment(attachment) do
        nil -> acc
        att -> Swoosh.Email.attachment(acc, att)
      end
    end)
  end

  defp build_attachment(%{"filename" => filename} = attachment) do
    content_type = attachment["content_type"]

    cond do
      is_binary(attachment["content_base64"]) ->
        content = Base.decode64!(attachment["content_base64"])
        Swoosh.Attachment.new({:data, content}, filename: filename, content_type: content_type)

      is_binary(attachment["path"]) ->
        Swoosh.Attachment.new(attachment["path"], filename: filename, content_type: content_type)

      true ->
        nil
    end
  end

  defp build_attachment(_), do: nil

  defp put_provider_options(email, message, delivery) do
    email
    |> Swoosh.Email.put_provider_option(:tags, [
      %{name: "category", value: to_string(message.category)},
      %{name: "template", value: message.template_key},
      %{name: "delivery_id", value: delivery.id}
    ])
    |> maybe_idempotency(message.idempotency_key)
  end

  defp maybe_idempotency(email, nil), do: email

  defp maybe_idempotency(email, key),
    do: Swoosh.Email.put_provider_option(email, :idempotency_key, key)

  defp mark_sent(delivery, response) do
    provider_ref = provider_ref(response)

    update_delivery(delivery, %{
      status: :sent,
      sent_at: now(),
      provider_ref: provider_ref,
      error: nil
    })

    record_ref(delivery, provider_ref)
    :ok
  end

  defp record_ref(_delivery, nil), do: :ok

  defp record_ref(delivery, provider_ref) do
    %DeliveryRef{}
    |> DeliveryRef.changeset(%{
      provider: "resend",
      provider_ref: provider_ref,
      tenant_id: delivery.tenant_id,
      delivery_id: delivery.id
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:provider, :provider_ref])

    :ok
  end

  defp handle_failure(job, delivery, reason) do
    error = inspect(reason)
    attempt = job.attempt || 1
    max_attempts = job.max_attempts || 5

    if attempt >= max_attempts do
      update_delivery(delivery, %{status: :failed, error: error})
      {:discard, reason}
    else
      update_delivery(delivery, %{error: error})
      {:error, reason}
    end
  end

  defp update_delivery(delivery, attrs) do
    delivery
    |> Delivery.changeset(attrs)
    |> Repo.update()
  end

  defp provider_ref(%{id: id}) when is_binary(id), do: id
  defp provider_ref(%{"id" => id}) when is_binary(id), do: id
  defp provider_ref(_response), do: nil

  defp subject_type(:customer_user), do: :customer_user
  defp subject_type(:staff_user), do: :staff_user
  defp subject_type(_), do: nil

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
