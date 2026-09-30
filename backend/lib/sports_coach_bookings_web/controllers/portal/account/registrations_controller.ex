defmodule SportsCoachBookingsWeb.Portal.Account.RegistrationsController do
  @moduledoc """
  Customer registration on a tenant host.

  The tenant is resolved from the host before this runs, so the account is always
  created for the host's tenant. Registration logs the customer in.
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookingsWeb.Customers.Helpers
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Portal.Auth
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:create,
    summary: "Register a customer for this tenant",
    request_body: {"Registration", "application/json", Schemas.registration_request()},
    responses: [
      created: {"Registered", "application/json", Schemas.registration_response()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/registrations"
  def create(conn, params) do
    attrs = Helpers.body(params, "customer_user")

    case Customers.register_customer(attrs) do
      {:ok, %{customer_user: customer_user, household: household}} ->
        conn
        |> Auth.log_in_customer(customer_user)
        |> put_status(:created)
        |> json(%{
          customer_user: CustomersJSON.customer_user(customer_user),
          household: CustomersJSON.household(household)
        })

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
