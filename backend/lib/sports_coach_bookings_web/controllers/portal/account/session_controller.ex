defmodule SportsCoachBookingsWeb.Portal.Account.SessionController do
  @moduledoc "Customer login/logout on a tenant host (host-only session cookie)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Portal.Auth
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:create,
    summary: "Log in a customer",
    request_body: {"Credentials", "application/json", Schemas.session_request()},
    responses: [
      created: {"Session", "application/json", Schemas.session_response()},
      unauthorized: {"Invalid credentials", "application/json", ErrorResponse},
      forbidden: {"Deactivated account", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/session"
  def create(conn, params) do
    with {:ok, email} <- fetch(params, "email"),
         {:ok, password} <- fetch(params, "password"),
         {:ok, customer_user} <- Customers.authenticate(email, password) do
      conn
      |> Auth.log_in_customer(customer_user)
      |> put_status(:created)
      |> json(%{customer_user: CustomersJSON.customer_user(customer_user)})
    else
      {:error, :deactivated} -> {:error, :account_deactivated}
      {:error, reason} -> {:error, reason}
    end
  end

  operation(:delete,
    summary: "Log out the current customer",
    responses: [no_content: {"Logged out", "application/json", Schemas.message()}]
  )

  @doc "DELETE /api/portal/session"
  def delete(conn, _params) do
    conn |> Auth.log_out_customer() |> send_resp(:no_content, "")
  end

  defp fetch(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:validation_error, "#{key} is required"}}
    end
  end
end
