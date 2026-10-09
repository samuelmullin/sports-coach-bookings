defmodule SportsCoachBookings.Notifications do
  @moduledoc """
  The email notification engine: enqueuing, template registry, delivery
  tracking, preferences, and suppression. Owned by WP-05.

  ## Sending

      Notifications.deliver(:sample, [%{type: :email, email: "a@b.com"}],
        %{name: "Alex", action_url: "https://example.com"},
        category: :transactional, idempotency_key: "order-123")

  Inserts a `messages` row plus one `deliveries` row per recipient and enqueues
  one `Notifications.DeliveryWorker` job per sendable delivery on the
  `:notifications` queue. `idempotency_key` is unique per tenant: sending the
  same key twice is a no-op that returns the original message.

  For compatibility with the WP-01/WP-02 notifier seams, the legacy
  `deliver(template_key, assigns, opts)` form is also accepted; it sends to
  `assigns[:email]`.
  """

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.DeliveryWorker
  alias SportsCoachBookings.Notifications.Layout
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Notifications.Preferences
  alias SportsCoachBookings.Notifications.Suppressions
  alias SportsCoachBookings.Notifications.Templates
  alias SportsCoachBookings.Notifications.Templates.Helpers
  alias SportsCoachBookings.Notifications.UnsubscribeToken
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Tenancy

  @categories [:transactional, :operational, :marketing]
  @retention_days 90
  @from_address "notifications@mail.sportscoachbookings.com"

  @type recipient :: %{
          type: :customer_user | :staff_user | :email,
          id: binary() | nil,
          email: binary()
        }

  @type result :: %{
          message: Message.t(),
          deliveries: [Delivery.t()],
          idempotent: boolean()
        }

  ## Sending

  @doc """
  Delivers `template_key` to `recipients` with `assigns`.

  Options:

    * `:category` — `:transactional` (default), `:operational`, or `:marketing`
    * `:attachments` — list of `%{filename, content_type, content: binary}` or
      `%{filename, content_type, path: path}`
    * `:idempotency_key` — unique per tenant; a repeat is a no-op
    * `:send_at` — a `DateTime`; the job is scheduled for this time

  Returns `{:ok, %{message: …, deliveries: […], idempotent: boolean}}` or
  `{:error, reason}`.
  """
  @spec deliver(atom() | String.t(), [recipient()], map(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def deliver(template_key, recipients, assigns, opts) when is_list(recipients) do
    tenant_id = TenantContext.get_tenant_id()
    category = normalize_category(Keyword.get(opts, :category, :transactional))
    assigns = normalize_assigns(assigns)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    with :ok <- require_tenant(tenant_id),
         {:ok, template} <- fetch_template(template_key),
         :ok <- Templates.validate_assigns(template_key, assigns),
         {:ok, recipients} <- normalize_recipients(recipients),
         :ok <- validate_category(category) do
      subject = template.subject(assigns)
      persist(template_key, subject, assigns, recipients, category, idempotency_key, opts)
    end
  end

  @doc false
  @spec deliver(atom() | String.t(), [recipient()], map()) :: {:ok, result()} | {:error, term()}
  def deliver(template_key, recipients, assigns) when is_list(recipients),
    do: deliver(template_key, recipients, assigns, [])

  @doc false
  # Legacy WP-01/WP-02 notifier seam: deliver(template, assigns, opts).
  @spec deliver(atom() | String.t(), map(), keyword()) :: {:ok, result()} | {:error, term()}
  def deliver(template_key, assigns, opts) when is_map(assigns) and is_list(opts),
    do: deliver(template_key, recipients_from_assigns(assigns), assigns, opts)

  ## Rendering / preview

  @doc """
  Renders a template with the shared layout.

  Options: `:tenant_id` (uses `Tenancy.branding_for_email/1`), or explicit
  `:branding` / `:contact_email`. Returns `{:ok, %{subject, html, text}}`.
  """
  @spec render(atom() | String.t(), map(), keyword()) ::
          {:ok, %{subject: String.t(), html: String.t(), text: String.t()}} | {:error, term()}
  def render(template_key, assigns, opts \\ []) do
    assigns = normalize_assigns(assigns)

    with {:ok, template} <- fetch_template(template_key),
         :ok <- Templates.validate_assigns(template_key, assigns) do
      tenant_id = Keyword.get(opts, :tenant_id)
      branding = Keyword.get(opts, :branding) || branding_for(tenant_id)
      contact_email = Keyword.get(opts, :contact_email) || contact_email_for(tenant_id)

      html =
        Layout.render(template.html(assigns), branding,
          contact_email: contact_email,
          category: Keyword.get(opts, :category)
        )

      {:ok, %{subject: template.subject(assigns), html: html, text: template.text(assigns)}}
    end
  end

  @doc "Renders every registered template with its sample assigns (dev preview)."
  @spec previews() :: [{String.t(), {:ok, map()} | {:error, term()}}]
  def previews do
    tenant_id = TenantContext.get_tenant_id()
    Enum.map(Templates.keys(), &{&1, preview(&1, tenant_id: tenant_id)})
  end

  @doc "Renders one registered template with its sample assigns (dev preview)."
  @spec preview(atom() | String.t(), keyword()) ::
          {:ok, %{subject: String.t(), html: String.t(), text: String.t()}} | {:error, term()}
  def preview(template_key, opts \\ []) do
    render(template_key, Templates.sample_assigns(template_key), opts)
  end

  ## Admin: delivery log and resend

  @doc """
  Paginates deliveries to `emails` from the last 90 days, newest first. Each
  delivery has its `:message` preloaded.
  """
  @spec deliveries_for_emails([binary()], map() | keyword()) ::
          %{data: [Delivery.t()], next_cursor: binary() | nil}
  def deliveries_for_emails(emails, params \\ %{}) when is_list(emails) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@retention_days, :day)
      |> DateTime.truncate(:microsecond)

    read(fn ->
      query =
        from(d in Delivery,
          join: m in Message,
          on: m.id == d.message_id,
          where: d.email in ^emails and d.inserted_at >= ^cutoff,
          preload: [:message]
        )

      {rows, cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc """
  Re-enqueues a failed/bounced delivery. Refuses suppressed addresses.
  Audited. Returns `{:ok, new_delivery}`.
  """
  @spec resend_delivery(term(), binary()) ::
          {:ok, Delivery.t()} | {:error, :not_found | :suppressed | Ecto.Changeset.t()}
  def resend_delivery(actor, delivery_id) do
    read(fn -> fetch_and_resend(actor, delivery_id) end)
  end

  defp fetch_and_resend(actor, delivery_id) do
    case Repo.get(Delivery, delivery_id) do
      nil -> {:error, :not_found}
      %Delivery{} = delivery -> resend_if_allowed(actor, delivery)
    end
  end

  defp resend_if_allowed(actor, delivery) do
    if Suppressions.suppressed?(delivery.tenant_id, delivery.email) do
      {:error, :suppressed}
    else
      do_resend(actor, delivery)
    end
  end

  @doc "Fetches a delivery (with message preloaded) for the tenant in context."
  @spec get_delivery(binary()) :: Delivery.t() | nil
  def get_delivery(id) do
    read(fn -> Repo.get(Delivery, id) |> maybe_preload() end)
  end

  ## Unsubscribe

  @doc """
  Applies a signed unsubscribe token: turns off marketing for a user subject, or
  suppresses a raw address. Returns `{:ok, :unsubscribed}` or `{:error, reason}`.
  """
  @spec unsubscribe(String.t()) :: {:ok, :unsubscribed} | {:error, term()}
  def unsubscribe(token) do
    case UnsubscribeToken.verify(token) do
      {:ok, payload} -> apply_unsubscribe(payload)
      {:error, _reason} -> {:error, :invalid_token}
    end
  end

  @doc "The email address new mail is sent from."
  @spec from_address() :: String.t()
  def from_address do
    Application.get_env(:sports_coach_bookings, :notifications_from_address, @from_address)
  end

  @doc "Builds the unsubscribe URL used in List-Unsubscribe headers."
  @spec unsubscribe_url(map()) :: String.t()
  def unsubscribe_url(%{} = data) do
    token = UnsubscribeToken.sign(data)
    Helpers.tenant_url(data[:tenant_id], "/unsubscribe/#{token}")
  end

  ## Internal: persistence

  defp persist(template_key, subject, assigns, recipients, category, idempotency_key, opts) do
    read(fn ->
      case existing_message(idempotency_key) do
        %Message{} = message ->
          {:ok,
           %{
             message: message,
             deliveries: deliveries_for_message(message.id),
             idempotent: true
           }}

        nil ->
          insert_and_enqueue(
            template_key,
            subject,
            assigns,
            recipients,
            category,
            idempotency_key,
            opts
          )
      end
    end)
  end

  defp insert_and_enqueue(template_key, subject, assigns, recipients, category, key, opts) do
    changeset =
      Message.changeset(%Message{}, %{
        tenant_id: TenantContext.get_tenant_id(),
        template_key: to_string(template_key),
        category: category,
        subject: subject,
        idempotency_key: key,
        assigns: json_safe(assigns)
      })

    with {:ok, message} <- Repo.insert(changeset),
         {:ok, deliveries} <- insert_deliveries(message, recipients, category),
         :ok <- enqueue_queued(deliveries, opts) do
      {:ok, %{message: message, deliveries: deliveries, idempotent: false}}
    end
  end

  defp insert_deliveries(message, recipients, category) do
    tenant_id = message.tenant_id

    deliveries =
      Enum.map(recipients, fn recipient ->
        status = status_for(recipient, message, category)

        changeset =
          Delivery.changeset(%Delivery{}, %{
            tenant_id: tenant_id,
            message_id: message.id,
            recipient_type: recipient.type,
            recipient_id: recipient.id,
            email: recipient.email,
            status: status
          })

        Repo.insert!(changeset)
      end)

    {:ok, deliveries}
  end

  defp status_for(recipient, message, category) do
    exempt = Templates.exempt_from_suppression?(message.template_key)

    cond do
      not exempt and Suppressions.suppressed?(message.tenant_id, recipient.email) -> :suppressed
      not Preferences.allowed?(recipient, category) -> :suppressed
      true -> :queued
    end
  end

  defp enqueue_queued(deliveries, opts) do
    deliveries
    |> Enum.filter(&(&1.status == :queued))
    |> Enum.reduce_while(:ok, fn delivery, :ok ->
      case enqueue(delivery, opts) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp enqueue(%Delivery{} = delivery, opts \\ []) do
    args = %{
      "delivery_id" => delivery.id,
      "tenant_id" => delivery.tenant_id,
      "attachments" => serialize_attachments(Keyword.get(opts, :attachments, []))
    }

    job_opts =
      opts
      |> Keyword.take([:send_at])
      |> Enum.map(fn {:send_at, at} -> {:scheduled_at, at} end)

    args
    |> DeliveryWorker.new(job_opts)
    |> Oban.insert()
  end

  defp serialize_attachments(attachments) when is_list(attachments) do
    Enum.map(attachments, fn attachment ->
      attachment = Map.new(attachment, fn {k, v} -> {to_string(k), v} end)

      base = %{
        "filename" => attachment["filename"],
        "content_type" => attachment["content_type"]
      }

      cond do
        is_binary(attachment["content"]) ->
          Map.put(base, "content_base64", Base.encode64(attachment["content"]))

        is_binary(attachment["path"]) ->
          Map.put(base, "path", attachment["path"])

        true ->
          base
      end
    end)
  end

  defp serialize_attachments(_attachments), do: []

  ## Internal: settings and lookups

  defp existing_message(nil), do: nil

  defp existing_message(idempotency_key) do
    Repo.get_by(Message,
      tenant_id: TenantContext.get_tenant_id(),
      idempotency_key: idempotency_key
    )
  end

  defp deliveries_for_message(message_id) do
    Repo.all(
      from d in Delivery, where: d.message_id == ^message_id, order_by: [asc: d.inserted_at]
    )
  end

  defp fetch_template(key) do
    case Templates.get(key) do
      nil -> {:error, {:unknown_template, to_string(key)}}
      module -> {:ok, module}
    end
  end

  defp branding_for(nil), do: %{}

  defp branding_for(tenant_id) do
    Tenancy.branding_for_email(tenant_id)
  rescue
    _ -> %{}
  end

  defp contact_email_for(nil), do: nil

  defp contact_email_for(tenant_id) do
    case Tenancy.get_tenant(tenant_id) do
      %{contact_email: email} -> email
      _ -> nil
    end
  end

  ## Internal: recipients / assigns / validation

  defp recipients_from_assigns(assigns) do
    email = Map.get(assigns, :email) || Map.get(assigns, "email")
    [%{type: :email, id: nil, email: email}]
  end

  defp normalize_recipients(recipients) do
    recipients
    |> Enum.reduce_while({:ok, []}, fn recipient, {:ok, acc} ->
      case normalize_recipient(recipient) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp normalize_recipient(%{} = recipient) do
    type = fetch(recipient, :type)
    email = fetch(recipient, :email)
    id = fetch(recipient, :id)

    cond do
      type not in [:customer_user, :staff_user, :email] ->
        {:error, {:invalid_recipient, recipient}}

      not (is_binary(email) and email != "") ->
        {:error, {:invalid_recipient, recipient}}

      true ->
        {:ok, %{type: type, id: id, email: email}}
    end
  end

  defp normalize_recipient(recipient), do: {:error, {:invalid_recipient, recipient}}

  defp normalize_assigns(assigns) when is_list(assigns),
    do: assigns |> Map.new() |> normalize_assigns()

  defp normalize_assigns(assigns) when is_map(assigns) do
    Map.new(assigns, fn {key, value} -> {to_atom(key), value} end)
  end

  defp to_atom(key) when is_atom(key), do: key

  # Only convert to an atom that already exists. Template variable names are
  # literals in the template source (so their atoms already exist); unknown keys
  # are left as strings to avoid atom-table exhaustion from untrusted input.
  defp to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp normalize_category(category) when is_binary(category) do
    case category do
      "transactional" -> :transactional
      "operational" -> :operational
      "marketing" -> :marketing
      _ -> nil
    end
  end

  defp normalize_category(category), do: category

  defp validate_category(category) when category in @categories, do: :ok
  defp validate_category(_category), do: {:error, :invalid_category}

  defp require_tenant(nil), do: {:error, :no_tenant}
  defp require_tenant(_tenant_id), do: :ok

  ## Internal: unsubscribe

  defp apply_unsubscribe(%{"subject_type" => type, "subject_id" => id, "tenant_id" => tenant_id})
       when type in ["customer_user", "staff_user"] and is_binary(id) and is_binary(tenant_id) do
    TenantContext.with_tenant(tenant_id, fn ->
      Repo.with_tenant_tx(fn ->
        Preferences.update({String.to_existing_atom(type), id}, %{marketing_opt_in: false})
      end)
    end)

    {:ok, :unsubscribed}
  end

  defp apply_unsubscribe(%{"email" => email, "tenant_id" => tenant_id})
       when is_binary(email) and is_binary(tenant_id) do
    TenantContext.with_tenant(tenant_id, fn ->
      Repo.with_tenant_tx(fn -> Suppressions.suppress(tenant_id, email, :complaint) end)
    end)

    {:ok, :unsubscribed}
  end

  defp apply_unsubscribe(_payload), do: {:error, :invalid_token}

  ## Internal: resend

  defp do_resend(actor, delivery) do
    message = Repo.get!(Message, delivery.message_id)

    changeset =
      Delivery.changeset(%Delivery{}, %{
        tenant_id: delivery.tenant_id,
        message_id: message.id,
        recipient_type: delivery.recipient_type,
        recipient_id: delivery.recipient_id,
        email: delivery.email,
        status: :queued
      })

    with {:ok, new_delivery} <- Repo.insert(changeset),
         {:ok, _} <-
           Audit.record(actor, "notifications.delivery.resent", new_delivery, %{
             original_delivery_id: delivery.id
           }),
         {:ok, _job} <- enqueue(new_delivery) do
      {:ok, new_delivery}
    end
  end

  ## Internal: serialisation / plumbing

  @doc false
  # Recursively stringifies map keys and values so assigns are JSON-safe.
  def json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def json_safe(%Date{} = value), do: Date.to_iso8601(value)
  def json_safe(%Time{} = value), do: Time.to_iso8601(value)

  def json_safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_safe(v)} end)

  def json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  def json_safe(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  def json_safe(value), do: value

  defp maybe_preload(nil), do: nil
  defp maybe_preload(delivery), do: Repo.preload(delivery, :message)

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  ## Privacy erasure

  @doc """
  Scrubs the given email addresses from delivery and broadcast-recipient
  records. The rows are kept (delivery counts and provider references matter for
  reconciliation) but no longer identify anyone. The suppression list is left
  untouched on purpose: erasing a bounced address from it would allow re-mailing.
  Called by `SportsCoachBookings.Privacy`.
  """
  @spec scrub_emails([binary()]) :: non_neg_integer()
  def scrub_emails([]), do: 0

  def scrub_emails(emails) do
    read(fn ->
      {deliveries, _} =
        Repo.update_all(from(d in Delivery, where: d.email in ^emails),
          set: [email: "erased@erased.invalid"]
        )

      {recipients, _} =
        Repo.update_all(
          from(r in SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient,
            where: r.email in ^emails
          ),
          set: [email: "erased@erased.invalid"]
        )

      deliveries + recipients
    end)
  end

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
