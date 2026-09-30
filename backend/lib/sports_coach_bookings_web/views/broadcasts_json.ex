defmodule SportsCoachBookingsWeb.BroadcastsJSON do
  @moduledoc "Serialises WP-17 broadcasts, recipients, and previews."

  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast

  @doc "Serialises a broadcast."
  @spec broadcast(Broadcast.t()) :: map()
  def broadcast(%Broadcast{} = broadcast) do
    %{
      id: broadcast.id,
      subject: broadcast.subject,
      body_markdown: broadcast.body_markdown,
      category: broadcast.category,
      segment: broadcast.segment,
      status: broadcast.status,
      scheduled_for: datetime(broadcast.scheduled_for),
      sent_at: datetime(broadcast.sent_at),
      created_by: broadcast.created_by,
      recipient_count: broadcast.recipient_count,
      stats: broadcast.stats,
      inserted_at: datetime(broadcast.inserted_at),
      updated_at: datetime(broadcast.updated_at)
    }
  end

  @doc "Wraps broadcasts in the pagination envelope."
  @spec collection([Broadcast.t()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil) do
    %{data: Enum.map(data, &broadcast/1), next_cursor: next_cursor}
  end

  @doc "Serialises a preview response."
  @spec preview(map()) :: map()
  def preview(preview) do
    %{
      subject: preview.subject,
      html: preview.html,
      text: preview.text,
      recipient_count: preview.recipient_count,
      recipients: preview.recipients
    }
  end

  @doc "Serialises a recipient-count response."
  @spec recipient_count(map()) :: map()
  def recipient_count(count) do
    %{
      recipient_count: count.recipient_count,
      marketing_filtered: count.marketing_filtered,
      recipients: count.recipients
    }
  end

  @doc "Serialises a send-test result."
  @spec test(map()) :: map()
  def test(result) do
    %{message_id: result.message_id, email: result.email, status: result.status}
  end

  @doc "Serialises a recipient with its live delivery status."
  @spec recipient(map()) :: map()
  def recipient(row) do
    %{
      id: row.id,
      email: row.email,
      recipient_type: row.recipient_type,
      status: row.status,
      delivery_status: row.delivery_status,
      message_id: row.message_id,
      delivery_id: row.delivery_id,
      sent_at: datetime(row.sent_at),
      error: row.error,
      inserted_at: datetime(row.inserted_at)
    }
  end

  @doc "Serialises a broadcast history response."
  @spec history(map()) :: map()
  def history(history) do
    %{
      broadcast: broadcast(history.broadcast),
      stats: history.stats,
      data: Enum.map(history.data, &recipient/1),
      next_cursor: history.next_cursor
    }
  end

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
