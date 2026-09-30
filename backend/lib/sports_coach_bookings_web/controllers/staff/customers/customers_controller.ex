defmodule SportsCoachBookingsWeb.Staff.Customers.CustomersController do
  @moduledoc "Staff (owner/admin) customer search, detail, and account management."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.Policy
  alias SportsCoachBookingsWeb.Customers.Helpers
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["staff"])

  operation(:index,
    summary: "Search/list customers",
    parameters: [
      q: [in: :query, type: :string, required: false, description: "name, email, or phone"],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Customers", "application/json", Schemas.customer_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/customers"
  def index(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :list, :customer) do
      %{data: data, next_cursor: cursor} = Customers.page_customers(term(params), params)
      json(conn, CustomersJSON.collection(Enum.map(data, &CustomersJSON.customer_user/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a customer",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Customer", "application/json", Schemas.customer_user()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/customers/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Policy.authorize(actor(conn), :get, :customer),
         {:ok, customer_user} <- fetch(id) do
      json(conn, CustomersJSON.customer_user(customer_user))
    end
  end

  operation(:update,
    summary: "Edit a customer's contact details",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Contact details", "application/json", Schemas.account_update_request()},
    responses: [
      ok: {"Customer", "application/json", Schemas.customer_user()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/customers/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Policy.authorize(actor(conn), :update, :customer),
         {:ok, customer_user} <-
           Customers.admin_update_customer(
             actor(conn),
             id,
             Helpers.body(params, "customer_user")
           ) do
      json(conn, CustomersJSON.customer_user(customer_user))
    end
  end

  operation(:reset_password,
    summary: "Trigger a password-reset email",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      accepted: {"Accepted", "application/json", Schemas.message()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/customers/:id/password_reset"
  def reset_password(conn, %{"id" => id}) do
    with :ok <- Policy.authorize(actor(conn), :reset_password, :customer),
         :ok <- Customers.trigger_password_reset(actor(conn), id) do
      conn
      |> put_status(:accepted)
      |> json(%{message: "If the customer exists, a reset email has been sent."})
    end
  end

  operation(:deactivate,
    summary: "Deactivate a customer (blocks login, retains data)",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Customer", "application/json", Schemas.customer_user()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/customers/:id/deactivate"
  def deactivate(conn, %{"id" => id}) do
    with :ok <- Policy.authorize(actor(conn), :deactivate, :customer),
         {:ok, customer_user} <- Customers.deactivate_customer(actor(conn), id) do
      json(conn, CustomersJSON.customer_user(customer_user))
    end
  end

  operation(:reactivate,
    summary: "Reactivate a customer",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Customer", "application/json", Schemas.customer_user()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/customers/:id/reactivate"
  def reactivate(conn, %{"id" => id}) do
    with :ok <- Policy.authorize(actor(conn), :reactivate, :customer),
         {:ok, customer_user} <- Customers.reactivate_customer(actor(conn), id) do
      json(conn, CustomersJSON.customer_user(customer_user))
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp fetch(id) do
    case Customers.get_customer_user(id) do
      nil -> {:error, :not_found}
      customer_user -> {:ok, customer_user}
    end
  end

  defp term(params) do
    Map.get(params, "q") || Map.get(params, "query")
  end
end
