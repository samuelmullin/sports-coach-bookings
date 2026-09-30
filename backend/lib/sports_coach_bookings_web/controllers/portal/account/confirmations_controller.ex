defmodule SportsCoachBookingsWeb.Portal.Account.ConfirmationsController do
  @moduledoc "Customer email confirmation on a tenant host."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:create,
    summary: "Confirm a customer email",
    request_body: {"Token", "application/json", Schemas.token_request()},
    responses: [
      ok: {"Confirmed", "application/json", Schemas.session_response()},
      not_found: {"Invalid token", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/confirmation"
  def create(conn, %{"token" => token}) do
    case Customers.confirm_customer_user(token) do
      {:ok, customer_user} ->
        json(conn, %{customer_user: CustomersJSON.customer_user(customer_user)})

      {:error, :invalid_token} ->
        {:error, :not_found}
    end
  end

  def create(_conn, _params), do: {:error, {:validation_error, "token is required"}}

  operation(:resend,
    summary: "Resend a customer confirmation email",
    request_body: {"Email", "application/json", Schemas.password_reset_request()},
    responses: [accepted: {"Accepted", "application/json", Schemas.message()}]
  )

  @doc "POST /api/portal/confirmation/resend"
  def resend(conn, %{"email" => email}) do
    case Customers.get_customer_user_by_email(email) do
      nil -> :ok
      customer_user -> Customers.deliver_confirmation_instructions(customer_user)
    end

    conn
    |> put_status(:accepted)
    |> json(%{message: "If the address exists, a confirmation email has been sent."})
  end
end
