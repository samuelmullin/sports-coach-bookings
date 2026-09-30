defmodule SportsCoachBookingsWeb.Portal.Account.PasswordResetController do
  @moduledoc "Customer password reset on a tenant host."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:create,
    summary: "Request a customer password reset",
    request_body: {"Email", "application/json", Schemas.password_reset_request()},
    responses: [accepted: {"Accepted", "application/json", Schemas.message()}]
  )

  @doc "POST /api/portal/password_reset"
  def create(conn, %{"email" => email}) do
    Customers.deliver_reset_password_instructions(email)

    conn
    |> put_status(:accepted)
    |> json(%{message: "If the address exists, a reset email has been sent."})
  end

  def create(_conn, _params), do: {:error, {:validation_error, "email is required"}}

  operation(:update,
    summary: "Apply a customer password reset",
    request_body: {"Reset", "application/json", Schemas.password_reset_update_request()},
    responses: [
      ok: {"Reset", "application/json", Schemas.session_response()},
      not_found: {"Invalid token", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PUT /api/portal/password_reset"
  def update(conn, %{"token" => token} = params) do
    case Customers.reset_password(token, %{"password" => params["password"]}) do
      {:ok, customer_user} ->
        json(conn, %{customer_user: CustomersJSON.customer_user(customer_user)})

      {:error, :invalid_token} ->
        {:error, :not_found}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(_conn, _params), do: {:error, {:validation_error, "token and password are required"}}
end
