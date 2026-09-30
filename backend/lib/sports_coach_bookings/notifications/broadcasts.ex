defmodule SportsCoachBookings.Notifications.Broadcasts do
  @moduledoc """
  Broadcast messaging to groups of customers. Owned by WP-17.

  Owners/admins write a broadcast (subject + Markdown body + category), target a
  segment of households, preview it, send a test, schedule it, and send it. The
  segment is resolved through the owning contexts' public query functions (see
  `Broadcasts.Segments`).

  ## Sending and idempotency

  A send resolves the segment to a de-duplicated list of manager emails, records
  one `broadcast_recipients` row per recipient (unique per
  `(tenant_id, broadcast_id, email)`), and enqueues `BatchWorker` jobs of 100
  recipients each. Each recipient is delivered through
  `Notifications.deliver/4` with the per-recipient idempotency key
  `"broadcast-<id>-<recipient_id>"`, so replaying a send or a batch never sends a
  second email for a recipient.

  Marketing broadcasts drop recipients without `marketing_opt_in` and suppressed
  addresses before sending; operational broadcasts include everyone in the
  (booking-based) segment.
  """

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Core.Types.UUIDv7
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Broadcasts.BatchWorker
  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast
  alias SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient
  alias SportsCoachBookings.Notifications.Broadcasts.Markdown
  alias SportsCoachBookings.Notifications.Broadcasts.ScheduleWorker
  alias SportsCoachBookings.Notifications.Broadcasts.Segment
  alias SportsCoachBookings.Notifications.Broadcasts.Segments
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Staff

  @template :broadcast
  @batch_size 100
  @preview_recipients 20

  ## Reads

  @doc "Paginates the tenant's broadcasts, newest first."
  @spec list_broadcasts(map() | keyword()) ::
          %{data: [Broadcast.t()], next_cursor: binary() | nil}
  def list_broadcasts(params \\ %{}) do
    read(fn ->
      {rows, cursor} = Pagination.paginate(from(b in Broadcast), params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc "Fetches a broadcast by id for the tenant in context, or `nil`."
  @spec get_broadcast(binary()) :: Broadcast.t() | nil
  def get_broadcast(id), do: read(fn -> Repo.get(Broadcast, id) end)

  @doc "Fetches a broadcast by id, or `{:error, :not_found}`."
  @spec fetch_broadcast(binary()) :: {:ok, Broadcast.t()} | {:error, :not_found}
  def fetch_broadcast(id), do: read(fn -> fetch_record(id) end)

  ## Writes

  @doc "Creates a draft broadcast."
  @spec create_broadcast(term(), map()) ::
          {:ok, Broadcast.t()} | {:error, Ecto.Changeset.t()}
  def create_broadcast(actor, attrs) do
    attrs =
      attrs
      |> stringify()
      |> Map.put("tenant_id", TenantContext.get_tenant_id())
      |> Map.put("created_by", actor_staff_id(actor))

    write(fn ->
      with {:ok, broadcast} <- %Broadcast{} |> Broadcast.changeset(attrs) |> Repo.insert(),
           {:ok, _audit} <-
             Audit.record(actor, "notifications.broadcast.created", broadcast, %{}) do
        {:ok, broadcast}
      end
    end)
  end

  @doc "Updates a draft or scheduled broadcast."
  @spec update_broadcast(term(), binary(), map()) ::
          {:ok, Broadcast.t()} | {:error, term()}
  def update_broadcast(actor, id, attrs) do
    write(fn ->
      with {:ok, broadcast} <- fetch_editable(id) do
        persist_update(actor, broadcast, attrs)
      end
    end)
  end

  @doc "Deletes a draft broadcast."
  @spec delete_broadcast(term(), binary()) :: {:ok, Broadcast.t()} | {:error, term()}
  def delete_broadcast(actor, id) do
    write(fn -> delete_in_tx(actor, id) end)
  end

  defp delete_in_tx(actor, id) do
    case fetch_record(id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %Broadcast{status: :draft} = broadcast} ->
        delete_draft(actor, broadcast)

      {:ok, %Broadcast{}} ->
        {:error, {:not_draft, "Only a draft broadcast can be deleted"}}
    end
  end

  defp delete_draft(actor, broadcast) do
    with {:ok, _audit} <-
           Audit.record(actor, "notifications.broadcast.deleted", broadcast, %{}) do
      Repo.delete(broadcast)
    end
  end

  @doc "Schedules a draft or already-scheduled broadcast for `scheduled_for`."
  @spec schedule(term(), binary(), DateTime.t() | binary()) ::
          {:ok, Broadcast.t()} | {:error, term()}
  def schedule(actor, id, scheduled_for) do
    with {:ok, at} <- parse_datetime(scheduled_for),
         :ok <- require_future(at) do
      write(fn -> schedule_in_tx(actor, id, at) end)
    end
  end

  defp schedule_in_tx(actor, id, at) do
    case fetch_record(id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %Broadcast{status: status} = broadcast} when status in [:draft, :scheduled] ->
        do_schedule(actor, broadcast, at)

      {:ok, %Broadcast{}} ->
        {:error, {:not_schedulable, "Only a draft or scheduled broadcast can be scheduled"}}
    end
  end

  @doc "Cancels a draft or scheduled broadcast."
  @spec cancel(term(), binary()) :: {:ok, Broadcast.t()} | {:error, term()}
  def cancel(actor, id) do
    write(fn ->
      case fetch_record(id) do
        {:error, reason} ->
          {:error, reason}

        {:ok, %Broadcast{status: :cancelled} = broadcast} ->
          {:ok, broadcast}

        {:ok, %Broadcast{status: status} = broadcast} when status in [:draft, :scheduled] ->
          do_cancel(actor, broadcast)

        {:ok, %Broadcast{}} ->
          {:error, {:not_cancellable, "Only a draft or scheduled broadcast can be cancelled"}}
      end
    end)
  end

  @doc "Sends the broadcast to its segment immediately. Idempotent per recipient."
  @spec send_now(term(), binary()) :: {:ok, Broadcast.t()} | {:error, term()}
  def send_now(actor, id) do
    start_send(id, require_due: false, actor: actor)
  end

  @doc "Resumes/executes a send if the broadcast is due. Used by the scheduler."
  @spec start_send(binary(), keyword()) :: {:ok, Broadcast.t() | :not_due} | {:error, term()}
  def start_send(broadcast_id, opts \\ []) do
    write(fn ->
      do_start(broadcast_id, Keyword.get(opts, :require_due, false), Keyword.get(opts, :actor))
    end)
  end

  ## Preview / counts

  @doc """
  Renders the broadcast (subject + HTML + text) and returns the live recipient
  count plus a sample of recipients.
  """
  @spec preview(binary()) :: {:ok, map()} | {:error, term()}
  def preview(id) do
    read(fn -> preview_in_tx(id) end)
  end

  defp preview_in_tx(id) do
    with {:ok, broadcast} <- fetch_record(id) do
      render_preview(broadcast)
    end
  end

  defp render_preview(broadcast) do
    recipients = Segments.recipients(broadcast.segment, broadcast.category)

    with {:ok, rendered} <-
           Notifications.render(@template, assigns(broadcast),
             tenant_id: broadcast.tenant_id,
             category: broadcast.category
           ) do
      {:ok,
       %{
         subject: rendered.subject,
         html: rendered.html,
         text: rendered.text,
         recipient_count: length(recipients),
         recipients: recipients |> Enum.take(@preview_recipients) |> Enum.map(& &1.email)
       }}
    end
  end

  @doc "The live recipient count for the broadcast's segment and category."
  @spec recipient_count(binary()) :: {:ok, map()} | {:error, term()}
  def recipient_count(id) do
    read(fn ->
      with {:ok, broadcast} <- fetch_record(id) do
        recipients = Segments.recipients(broadcast.segment, broadcast.category)

        {:ok,
         %{
           recipient_count: length(recipients),
           marketing_filtered: broadcast.category == :marketing,
           recipients: recipients |> Enum.take(@preview_recipients) |> Enum.map(& &1.email)
         }}
      end
    end)
  end

  @doc """
  Sends a one-off test of the broadcast to `email` (defaults to the requesting
  staff user's address).

  Test sends are operational so they always reach the requested address
  regardless of marketing opt-in.
  """
  @spec send_test(term(), binary(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def send_test(actor, id, email \\ nil) do
    write(fn ->
      with {:ok, broadcast} <- fetch_record(id),
           {:ok, recipient} <- test_recipient(actor, email) do
        do_send_test(actor, broadcast, recipient)
      end
    end)
  end

  ## History / stats

  @doc """
  Returns the broadcast with live delivery stats and a page of its recipients.

  Each recipient carries the WP-05 delivery status (`delivered`, `bounced`, …).
  """
  @spec history(binary(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def history(id, params \\ %{}) do
    read(fn -> history_in_tx(id, params) end)
  end

  defp history_in_tx(id, params) do
    with {:ok, broadcast} <- fetch_record(id) do
      build_history(broadcast, params)
    end
  end

  defp build_history(broadcast, params) do
    {rows, cursor} =
      Pagination.paginate(
        from(r in BroadcastRecipient, where: r.broadcast_id == ^broadcast.id),
        params
      )

    deliveries = deliveries_for(rows)

    data =
      Enum.map(rows, &recipient_row(&1, Map.get(deliveries, &1.delivery_id)))

    {:ok,
     %{
       broadcast: broadcast,
       stats: stats(broadcast.id),
       data: data,
       next_cursor: cursor
     }}
  end

  ## Worker entry points

  @doc false
  @spec process_batch(binary(), integer()) :: :ok | {:error, term()}
  def process_batch(broadcast_id, batch) do
    case Repo.with_tenant_tx(fn -> do_process_batch(broadcast_id, batch) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_process_batch(broadcast_id, batch) do
    case Repo.get(Broadcast, broadcast_id) do
      %Broadcast{status: :cancelled} -> :ok
      %Broadcast{} = broadcast -> process_recipients(broadcast, batch)
      nil -> :ok
    end
  end

  ## Internal: send

  defp do_start(broadcast_id, require_due, actor) do
    case Repo.get(Broadcast, broadcast_id) do
      nil ->
        {:error, :not_found}

      %Broadcast{status: :cancelled} ->
        {:error, :cancelled}

      %Broadcast{} = broadcast ->
        cond do
          require_due and not due?(broadcast) -> {:ok, :not_due}
          broadcast.status == :sent and pending_count(broadcast.id) == 0 -> {:ok, broadcast}
          true -> begin_send(broadcast, actor)
        end
    end
  end

  defp begin_send(broadcast, actor) do
    recipients = Segments.recipients(broadcast.segment, broadcast.category)
    now = now()

    upsert_recipients(recipient_rows(broadcast, recipients, now))
    total = stored_recipient_count(broadcast.id)
    batches = div(total + @batch_size - 1, @batch_size)

    {:ok, updated} =
      broadcast
      |> Broadcast.status_changeset(%{status: :sending, recipient_count: total})
      |> Repo.update()

    if actor do
      _ =
        Audit.record(actor, "notifications.broadcast.sent", updated, %{
          recipient_count: total,
          batch_count: batches
        })
    end

    if total == 0 do
      finalize(broadcast.id)
    else
      enqueue_batches(updated, batches)
      {:ok, updated}
    end
  end

  defp finalize(broadcast_id) do
    case Repo.get(Broadcast, broadcast_id) do
      %Broadcast{status: :cancelled} = broadcast ->
        {:ok, broadcast}

      %Broadcast{} = broadcast ->
        if pending_count(broadcast_id) == 0 do
          broadcast
          |> Broadcast.status_changeset(%{
            status: :sent,
            sent_at: broadcast.sent_at || now(),
            stats: stats(broadcast_id)
          })
          |> Repo.update()
        else
          {:ok, broadcast}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp process_recipients(broadcast, batch) do
    recipients =
      Repo.all(
        from r in BroadcastRecipient,
          where:
            r.broadcast_id == ^broadcast.id and r.batch_index == ^batch and
              r.status == :pending,
          order_by: [asc: r.inserted_at, asc: r.id]
      )

    Enum.each(recipients, &send_recipient(broadcast, &1))
    finalize(broadcast.id)
    :ok
  end

  defp send_recipient(broadcast, recipient) do
    key = "broadcast-#{broadcast.id}-#{recipient.id}"

    opts = [category: broadcast.category, idempotency_key: key]

    case Notifications.deliver(
           @template,
           [recipient_map(recipient)],
           assigns(broadcast),
           opts
         ) do
      {:ok, %{deliveries: [delivery | _]}} -> record_delivery(recipient, delivery)
      {:ok, %{deliveries: []}} -> mark_failed(recipient, :no_delivery)
      {:error, reason} -> mark_failed(recipient, reason)
    end
  end

  defp record_delivery(recipient, delivery) do
    status = delivery_recipient_status(delivery.status)

    recipient
    |> BroadcastRecipient.changeset(%{
      message_id: delivery.message_id,
      delivery_id: delivery.id,
      status: status,
      sent_at: if(status == :sent, do: now()),
      error: nil
    })
    |> Repo.update()
  end

  defp delivery_recipient_status(status) when status in [:queued, :sent, :delivered], do: :sent
  defp delivery_recipient_status(:suppressed), do: :suppressed
  defp delivery_recipient_status(_status), do: :failed

  defp mark_failed(recipient, reason) do
    recipient
    |> BroadcastRecipient.changeset(%{status: :failed, error: inspect(reason)})
    |> Repo.update()
  end

  defp recipient_rows(broadcast, recipients, now) do
    recipients
    |> Enum.with_index()
    |> Enum.map(fn {recipient, index} ->
      %{
        id: UUIDv7.generate(),
        tenant_id: broadcast.tenant_id,
        broadcast_id: broadcast.id,
        recipient_type: recipient.type,
        recipient_id: recipient.id,
        email: recipient.email,
        household_id: recipient.household_id,
        status: :pending,
        batch_index: div(index, @batch_size),
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  defp upsert_recipients([]), do: :ok

  defp upsert_recipients(rows) do
    Repo.insert_all(BroadcastRecipient, rows,
      on_conflict: :nothing,
      conflict_target: [:tenant_id, :broadcast_id, :email]
    )

    :ok
  end

  defp enqueue_batches(broadcast, count) do
    Enum.each(0..(count - 1), fn batch ->
      %{"tenant_id" => broadcast.tenant_id, "broadcast_id" => broadcast.id, "batch" => batch}
      |> BatchWorker.new()
      |> Oban.insert()
    end)
  end

  ## Internal: schedule / cancel

  defp do_schedule(actor, broadcast, at) do
    with {:ok, updated} <-
           broadcast
           |> Broadcast.status_changeset(%{status: :scheduled, scheduled_for: at})
           |> Repo.update(),
         {:ok, _job} <- enqueue_schedule(updated),
         {:ok, _audit} <-
           Audit.record(actor, "notifications.broadcast.scheduled", updated, %{
             scheduled_for: at
           }) do
      {:ok, updated}
    end
  end

  defp enqueue_schedule(broadcast) do
    %{"tenant_id" => broadcast.tenant_id, "broadcast_id" => broadcast.id}
    |> ScheduleWorker.new(scheduled_at: broadcast.scheduled_for)
    |> Oban.insert()
  end

  defp do_cancel(actor, broadcast) do
    with {:ok, updated} <-
           broadcast
           |> Broadcast.status_changeset(%{status: :cancelled})
           |> Repo.update(),
         {:ok, _audit} <-
           Audit.record(actor, "notifications.broadcast.cancelled", updated, %{}) do
      {:ok, updated}
    end
  end

  ## Internal: test send

  defp test_recipient(_actor, email) when is_binary(email) and email != "" do
    {:ok, %{type: :email, id: nil, email: String.downcase(email)}}
  end

  defp test_recipient(%StaffActor{staff_user_id: staff_user_id}, _email) do
    case Staff.get_staff_user(staff_user_id) do
      %{email: email} when is_binary(email) ->
        {:ok, %{type: :staff_user, id: staff_user_id, email: email}}

      _ ->
        {:error, :no_test_recipient}
    end
  end

  defp test_recipient(_actor, _email), do: {:error, :no_test_recipient}

  defp do_send_test(actor, broadcast, recipient) do
    case Notifications.deliver(@template, [recipient], assigns(broadcast),
           category: :operational,
           idempotency_key: test_key(broadcast)
         ) do
      {:ok, %{message: message, deliveries: deliveries}} ->
        _ =
          Audit.record(actor, "notifications.broadcast.test_sent", broadcast, %{
            to: recipient.email
          })

        {:ok,
         %{
           message_id: message.id,
           email: recipient.email,
           status: List.first(deliveries).status
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_key(broadcast),
    do: "broadcast-test-#{broadcast.id}-#{System.unique_integer([:positive])}"

  ## Internal: rendering

  defp assigns(broadcast) do
    %{
      subject: broadcast.subject,
      body_html: Markdown.to_html(broadcast.body_markdown),
      body_text: broadcast.body_markdown
    }
  end

  defp recipient_map(%BroadcastRecipient{} = recipient) do
    %{type: recipient.recipient_type, id: recipient.recipient_id, email: recipient.email}
  end

  ## Internal: history / stats

  defp deliveries_for([]), do: %{}

  defp deliveries_for(rows) do
    ids = rows |> Enum.map(& &1.delivery_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      Repo.all(from d in Delivery, where: d.id in ^ids) |> Map.new(&{&1.id, &1})
    end
  end

  defp recipient_row(recipient, delivery) do
    %{
      id: recipient.id,
      email: recipient.email,
      recipient_type: recipient.recipient_type,
      status: recipient.status,
      delivery_status: delivery && delivery.status,
      message_id: recipient.message_id,
      delivery_id: recipient.delivery_id,
      sent_at: recipient.sent_at,
      error: recipient.error,
      inserted_at: recipient.inserted_at
    }
  end

  defp stats(broadcast_id) do
    rows =
      Repo.all(
        from r in BroadcastRecipient,
          left_join: d in Delivery,
          on: d.id == r.delivery_id,
          where: r.broadcast_id == ^broadcast_id,
          select: {r.status, d.status}
      )

    counts =
      Enum.reduce(rows, %{}, fn {recipient_status, delivery_status}, acc ->
        key = to_string(delivery_status || recipient_status)
        Map.update(acc, key, 1, &(&1 + 1))
      end)

    Map.put(counts, "total", length(rows))
  end

  defp stored_recipient_count(broadcast_id) do
    Repo.one(
      from r in BroadcastRecipient,
        where: r.broadcast_id == ^broadcast_id,
        select: count(r.id)
    )
  end

  defp pending_count(broadcast_id) do
    Repo.one(
      from r in BroadcastRecipient,
        where: r.broadcast_id == ^broadcast_id and r.status == :pending,
        select: count(r.id)
    )
  end

  ## Internal: helpers

  defp fetch_record(id) do
    case Repo.get(Broadcast, id) do
      nil -> {:error, :not_found}
      broadcast -> {:ok, broadcast}
    end
  end

  defp fetch_editable(id) do
    case fetch_record(id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %Broadcast{status: status} = broadcast} when status in [:draft, :scheduled] ->
        {:ok, broadcast}

      {:ok, %Broadcast{}} ->
        {:error, {:not_editable, "Only a draft or scheduled broadcast can be edited"}}
    end
  end

  defp persist_update(actor, broadcast, attrs) do
    case broadcast |> Broadcast.changeset(stringify(attrs)) |> Repo.update() do
      {:ok, updated} ->
        _ = Audit.record(actor, "notifications.broadcast.updated", updated, %{})
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp due?(%Broadcast{scheduled_for: nil}), do: false

  defp due?(%Broadcast{scheduled_for: scheduled_for}) do
    DateTime.compare(scheduled_for, now()) != :gt
  end

  defp require_future(%DateTime{} = at) do
    if DateTime.compare(at, now()) == :gt,
      do: :ok,
      else: {:error, {:invalid_schedule, "scheduled_for must be in the future"}}
  end

  defp parse_datetime(%DateTime{} = value), do: {:ok, value}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
          {:error, _} -> {:error, {:invalid_schedule, "invalid scheduled_for"}}
        end
    end
  end

  defp parse_datetime(_), do: {:error, {:invalid_schedule, "invalid scheduled_for"}}

  defp actor_staff_id(%StaffActor{staff_user_id: id}), do: id
  defp actor_staff_id(_actor), do: nil

  defp stringify(attrs) when is_list(attrs), do: attrs |> Enum.into(%{}) |> stringify()

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp write(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec segment_types() :: [String.t()]
  def segment_types, do: Segment.types()
end
