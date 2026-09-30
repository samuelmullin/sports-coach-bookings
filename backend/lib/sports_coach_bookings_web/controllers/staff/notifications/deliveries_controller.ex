defmodule SportsCoachBookingsWeb.Staff.Notifications.DeliveriesController do
  @moduledoc "Staff (owner/admin) delivery log and resend."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Policy
  alias SportsCoachBookingsWeb.NotificationsJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Notifications, as: Schemas

  tags(["staff"])

  operation(:index,
    summary: "Delivery log for a customer, household, or email (last 90 days)",
    parameters: [
      customer_id: [in: :query, type: :string, required: false],
      household_id: [in: :query, type: :string, required: false],
      email: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Deliveries", "application/json", Schemas.delivery_list()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/notifications/deliveries"
  def index(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :view_delivery_log, :notifications),
         {:ok, emails} <- emails_for(params) do
      %{data: data, next_cursor: cursor} = Notifications.deliveries_for_emails(emails, params)

      json(
        conn,
        NotificationsJSON.collection(Enum.map(data, &NotificationsJSON.delivery/1), cursor)
      )
    end
  end

  operation(:resend,
    summary: "Resend a failed or bounced delivery",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Delivery", "application/json", Schemas.delivery()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Suppressed or validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/notifications/deliveries/:id/resend"
  def resend(conn, %{"id" => id}) do
    with :ok <- Policy.authorize(actor(conn), :resend_delivery, :notifications),
         {:ok, delivery} <- Notifications.resend_delivery(actor(conn), id) do
      json(conn, NotificationsJSON.delivery(delivery))
    end
  end

  defp emails_for(%{"customer_id" => id}) when is_binary(id) and id != "" do
    case Customers.get_customer_user(id) do
      nil -> {:error, :not_found}
      customer_user -> {:ok, [customer_user.email]}
    end
  end

  defp emails_for(%{"household_id" => id}) when is_binary(id) and id != "" do
    {:ok, Customers.list_manager_emails(id)}
  end

  defp emails_for(%{"email" => email}) when is_binary(email) and email != "", do: {:ok, [email]}

  defp emails_for(_params), do: {:error, :missing_filter}

  defp actor(conn), do: conn.assigns[:current_staff_actor]
end
