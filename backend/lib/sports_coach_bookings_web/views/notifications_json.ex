defmodule SportsCoachBookingsWeb.NotificationsJSON do
  @moduledoc "Serialises notification deliveries for the admin API."

  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.Message

  @doc "Serialises a delivery, including its message fields when preloaded."
  @spec delivery(Delivery.t()) :: map()
  def delivery(%Delivery{} = delivery) do
    %{
      id: delivery.id,
      message_id: delivery.message_id,
      template_key: message_field(delivery, :template_key),
      category: message_field(delivery, :category),
      subject: message_field(delivery, :subject),
      recipient_type: delivery.recipient_type,
      recipient_id: delivery.recipient_id,
      email: delivery.email,
      status: delivery.status,
      provider_ref: delivery.provider_ref,
      sent_at: datetime(delivery.sent_at),
      delivered_at: datetime(delivery.delivered_at),
      bounced_at: datetime(delivery.bounced_at),
      error: delivery.error,
      inserted_at: datetime(delivery.inserted_at)
    }
  end

  defp message_field(%Delivery{message: %Message{} = message}, field), do: Map.get(message, field)
  defp message_field(_delivery, _field), do: nil

  @doc "Wraps a list of serialised deliveries in the paginated envelope."
  @spec collection([map()], binary() | nil) :: map()
  def collection(data, cursor), do: %{data: data, next_cursor: cursor}

  @doc "Serialises a message (unused by endpoints today; kept for tooling)."
  @spec message(Message.t()) :: map()
  def message(%Message{} = message) do
    %{
      id: message.id,
      template_key: message.template_key,
      category: message.category,
      subject: message.subject,
      idempotency_key: message.idempotency_key,
      inserted_at: datetime(message.inserted_at)
    }
  end

  defp datetime(nil), do: nil
  defp datetime(value), do: DateTime.to_iso8601(value)
end
