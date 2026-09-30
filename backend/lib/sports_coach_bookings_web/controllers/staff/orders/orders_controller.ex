defmodule SportsCoachBookingsWeb.Staff.Orders.OrdersController do
  @moduledoc "Staff: order list/detail, refunds, and offline orders."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Commerce.Policy
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookingsWeb.CommerceJSON
  alias SportsCoachBookingsWeb.Schemas.Commerce, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["staff"])

  operation(:index,
    summary: "List orders",
    parameters: [
      status: [in: :query, type: :string, required: false],
      household_id: [in: :query, type: :string, required: false],
      type: [in: :query, type: :string, required: false],
      from: [in: :query, type: :string, required: false],
      to: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Orders", "application/json", Schemas.order_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/orders"
  def index(conn, params) do
    with :ok <- authorize(conn, :list, :order) do
      filters = Map.take(params, ["status", "household_id", "type", "from", "to"])
      %{data: data, next_cursor: cursor} = Commerce.page_orders(filters, params)

      json(conn, CommerceJSON.collection(Enum.map(data, &CommerceJSON.order/1), cursor))
    end
  end

  operation(:show,
    summary: "Get an order",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Order", "application/json", Schemas.order()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/orders/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- authorize(conn, :get, :order),
         {:ok, order} <- Commerce.fetch_order(id) do
      json(conn, CommerceJSON.order(order))
    end
  end

  operation(:refund,
    summary: "Refund an order line (or every open line)",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Refund", "application/json", Schemas.refund_request()},
    responses: [
      ok: {"Refund", "application/json", Schemas.refund_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Refund error", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/orders/:id/refund"
  def refund(conn, %{"id" => order_id} = params) do
    with :ok <- authorize(conn, :refund, :order),
         {:ok, order} <- Commerce.fetch_order(order_id) do
      refund_order_or_line(conn, order, params)
    end
  end

  operation(:create_offline,
    summary: "Create an already-paid order for a household",
    request_body: {"Offline order", "application/json", Schemas.offline_order_request()},
    responses: [
      created: {"Order", "application/json", Schemas.order()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/orders"
  def create_offline(conn, params) do
    with :ok <- authorize(conn, :create_offline, :order) do
      attrs = body(params)

      case Commerce.create_offline_order(actor(conn), attrs) do
        {:ok, order} -> conn |> put_status(:created) |> json(CommerceJSON.order(order))
        {:error, reason} -> {:error, reason}
      end
    end
  end

  ## Helpers

  defp refund_order_or_line(conn, order, params) do
    case field(params, :order_line_id) do
      nil -> refund_all(conn, order, params)
      line_id -> refund_one(conn, order, line_id, params)
    end
  end

  defp refund_all(conn, order, params) do
    opts = [reason: reason(params), force: force(params)]

    case Commerce.refund_order(actor(conn), order.id, opts) do
      {:ok, results} -> json(conn, %{refunds: Enum.map(results, &refund_result(&1, "refunded"))})
      {:error, reason} -> {:error, reason}
    end
  end

  defp refund_one(conn, order, line_id, params) do
    case Enum.find(order.lines, &(&1.id == line_id)) do
      nil ->
        {:error, :not_found}

      line ->
        amount = field(params, :amount) || line.line_total - line.refunded_amount
        money = Money.new(amount, order.currency)
        opts = [force: force(params)]

        case Commerce.refund_line(line.id, money, reason(params), actor(conn), opts) do
          {:ok, :already_refunded} ->
            json(conn, %{
              refunds: [
                %{
                  line: CommerceJSON.order_line(line),
                  payment_refunded: false,
                  status: "already_refunded"
                }
              ]
            })

          {:ok, result} ->
            json(conn, %{refunds: [refund_result(result, "refunded")]})

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp refund_result(%{line: line, payment_refund: payment_refund}, status) do
    %{
      line: CommerceJSON.order_line(line),
      payment_refunded: not is_nil(payment_refund),
      status: status
    }
  end

  defp authorize(conn, action, resource) do
    Policy.authorize(actor(conn), action, resource)
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp body(params) do
    case Map.get(params, "order") do
      %{} = order -> order
      _ -> Map.drop(params, ["id"])
    end
  end

  defp reason(params), do: field(params, :reason) || "requested_by_customer"
  defp force(params), do: field(params, :force) == true

  defp field(params, key) when is_map(params) do
    Map.get(params, to_string(key)) || Map.get(params, key)
  end
end
