defmodule SportsCoachBookingsWeb.Staff.Broadcasts.BroadcastsController do
  @moduledoc "Staff (owner/admin) broadcast messaging."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Notifications.Broadcasts
  alias SportsCoachBookings.Notifications.Broadcasts.Policy
  alias SportsCoachBookingsWeb.BroadcastsJSON
  alias SportsCoachBookingsWeb.Schemas.Broadcasts, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["staff"])

  operation(:index,
    summary: "List broadcasts",
    parameters: [
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Broadcasts", "application/json", Schemas.broadcast_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/broadcasts"
  def index(conn, params) do
    with :ok <- authorize(conn, :list, :broadcasts) do
      %{data: data, next_cursor: cursor} = Broadcasts.list_broadcasts(params)
      json(conn, BroadcastsJSON.collection(data, cursor))
    end
  end

  operation(:create,
    summary: "Create a draft broadcast",
    request_body: {"Broadcast", "application/json", Schemas.create_request()},
    responses: [
      created: {"Broadcast", "application/json", Schemas.broadcast()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/broadcasts"
  def create(conn, params) do
    with :ok <- authorize(conn, :create, :broadcasts),
         {:ok, broadcast} <- Broadcasts.create_broadcast(actor(conn), body(params, "broadcast")) do
      conn |> put_status(:created) |> json(BroadcastsJSON.broadcast(broadcast))
    end
  end

  operation(:show,
    summary: "Get a broadcast",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Broadcast", "application/json", Schemas.broadcast()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/broadcasts/:id"
  def show(conn, %{"id" => id}) do
    with {:ok, broadcast} <- fetch(conn, :view, id) do
      json(conn, BroadcastsJSON.broadcast(broadcast))
    end
  end

  operation(:update,
    summary: "Update a draft or scheduled broadcast",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Broadcast", "application/json", Schemas.update_request()},
    responses: [
      ok: {"Broadcast", "application/json", Schemas.broadcast()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH/PUT /api/staff/broadcasts/:id"
  def update(conn, %{"id" => id} = params) do
    with {:ok, broadcast} <- fetch(conn, :update, id),
         :ok <- Policy.authorize(actor(conn), :update, broadcast),
         {:ok, updated} <-
           Broadcasts.update_broadcast(actor(conn), id, body(params, "broadcast")) do
      json(conn, BroadcastsJSON.broadcast(updated))
    end
  end

  operation(:delete,
    summary: "Delete a draft broadcast",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      no_content: "Deleted",
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Not a draft", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/staff/broadcasts/:id"
  def delete(conn, %{"id" => id}) do
    with {:ok, broadcast} <- fetch(conn, :delete, id),
         :ok <- Policy.authorize(actor(conn), :delete, broadcast),
         {:ok, _deleted} <- Broadcasts.delete_broadcast(actor(conn), id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:recipients,
    summary: "Live recipient count and sample for a broadcast",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Recipient count", "application/json", Schemas.recipient_count_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/broadcasts/:id/recipients"
  def recipients(conn, %{"id" => id}) do
    with {:ok, broadcast} <- fetch(conn, :count_recipients, id),
         :ok <- Policy.authorize(actor(conn), :count_recipients, broadcast),
         {:ok, count} <- Broadcasts.recipient_count(id) do
      json(conn, BroadcastsJSON.recipient_count(count))
    end
  end

  operation(:preview,
    summary: "Render a broadcast and show its live recipients",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Preview", "application/json", Schemas.preview_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/broadcasts/:id/preview"
  def preview(conn, %{"id" => id}) do
    with {:ok, broadcast} <- fetch(conn, :preview, id),
         :ok <- Policy.authorize(actor(conn), :preview, broadcast),
         {:ok, preview} <- Broadcasts.preview(id) do
      json(conn, BroadcastsJSON.preview(preview))
    end
  end

  operation(:send_test,
    summary: "Send a test of the broadcast to an address (defaults to the caller)",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Test", "application/json", Schemas.test_request()},
    responses: [
      ok: {"Test delivery", "application/json", Schemas.test_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/broadcasts/:id/test"
  def send_test(conn, %{"id" => id} = params) do
    with {:ok, broadcast} <- fetch(conn, :send_test, id),
         :ok <- Policy.authorize(actor(conn), :send_test, broadcast),
         {:ok, result} <- Broadcasts.send_test(actor(conn), id, test_email(params)) do
      json(conn, BroadcastsJSON.test(result))
    end
  end

  operation(:schedule,
    summary: "Schedule a broadcast",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Schedule", "application/json", Schemas.schedule_request()},
    responses: [
      ok: {"Broadcast", "application/json", Schemas.broadcast()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/broadcasts/:id/schedule"
  def schedule(conn, %{"id" => id} = params) do
    with {:ok, broadcast} <- fetch(conn, :schedule, id),
         :ok <- Policy.authorize(actor(conn), :schedule, broadcast),
         {:ok, updated} <-
           Broadcasts.schedule(actor(conn), id, scheduled_for(params)) do
      json(conn, BroadcastsJSON.broadcast(updated))
    end
  end

  operation(:send_now,
    summary: "Send a broadcast to its segment now",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Broadcast", "application/json", Schemas.broadcast()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Not sendable", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/broadcasts/:id/send"
  def send_now(conn, %{"id" => id}) do
    with {:ok, broadcast} <- fetch(conn, :send, id),
         :ok <- Policy.authorize(actor(conn), :send, broadcast),
         {:ok, updated} <- Broadcasts.send_now(actor(conn), id) do
      json(conn, BroadcastsJSON.broadcast(updated))
    end
  end

  operation(:cancel,
    summary: "Cancel a draft or scheduled broadcast",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Broadcast", "application/json", Schemas.broadcast()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Not cancellable", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/broadcasts/:id/cancel"
  def cancel(conn, %{"id" => id}) do
    with {:ok, broadcast} <- fetch(conn, :cancel, id),
         :ok <- Policy.authorize(actor(conn), :cancel, broadcast),
         {:ok, updated} <- Broadcasts.cancel(actor(conn), id) do
      json(conn, BroadcastsJSON.broadcast(updated))
    end
  end

  operation(:history,
    summary: "Broadcast history with live delivery stats",
    parameters: [
      id: [in: :path, type: :string, required: true],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"History", "application/json", Schemas.history_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/broadcasts/:id/history"
  def history(conn, %{"id" => id} = params) do
    with {:ok, broadcast} <- fetch(conn, :history, id),
         :ok <- Policy.authorize(actor(conn), :history, broadcast),
         {:ok, history} <- Broadcasts.history(id, params) do
      json(conn, BroadcastsJSON.history(history))
    end
  end

  ## Internal

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  defp fetch(conn, action, id) do
    with :ok <- authorize(conn, action, :broadcasts) do
      Broadcasts.fetch_broadcast(id)
    end
  end

  defp test_email(params) do
    case body(params, "test") do
      %{"email" => email} when is_binary(email) and email != "" -> email
      _ -> nil
    end
  end

  defp scheduled_for(params) do
    case body(params, "schedule") do
      %{"scheduled_for" => value} -> value
      _ -> nil
    end
  end

  defp body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["id", "cursor", "limit", key])
    end
  end
end
