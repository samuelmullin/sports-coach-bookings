defmodule SportsCoachBookingsWeb.Staff.Policies.PoliciesController do
  @moduledoc "Staff CRUD, default/assignment management, and simulation for policies."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Policies
  alias SportsCoachBookingsWeb.Policies.Helpers
  alias SportsCoachBookingsWeb.PoliciesJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Policies.AssignmentListResponse
  alias SportsCoachBookingsWeb.Schemas.Policies.AssignmentRemovalResponse
  alias SportsCoachBookingsWeb.Schemas.Policies.AssignmentRequest
  alias SportsCoachBookingsWeb.Schemas.Policies.PolicyListResponse
  alias SportsCoachBookingsWeb.Schemas.Policies.PolicyRequest
  alias SportsCoachBookingsWeb.Schemas.Policies.PolicyResponse
  alias SportsCoachBookingsWeb.Schemas.Policies.SimulationRequest
  alias SportsCoachBookingsWeb.Schemas.Policies.SimulationResponse

  tags(["staff"])

  operation(:index,
    summary: "List cancellation policies",
    parameters: [
      active: [in: :query, type: :boolean, required: false],
      is_default: [in: :query, type: :boolean, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [ok: {"Cancellation policies", "application/json", PolicyListResponse}]
  )

  @doc "GET /api/staff/policies"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list, :cancellation_policy) do
      filters = Map.take(params, ["active", "is_default"])
      %{data: data, next_cursor: cursor} = Policies.page_policies(filters, params)

      json(conn, PoliciesJSON.collection(Enum.map(data, &serialize/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a cancellation policy",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Cancellation policy", "application/json", PolicyResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/policies/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :get, :cancellation_policy),
         {:ok, policy} <- Policies.fetch_policy(id) do
      json(conn, serialize(policy))
    end
  end

  operation(:create,
    summary: "Create a cancellation policy",
    request_body: {"Cancellation policy", "application/json", PolicyRequest},
    responses: [
      created: {"Cancellation policy", "application/json", PolicyResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/policies"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :create, :cancellation_policy),
         {:ok, policy} <-
           Policies.create_policy(Helpers.actor(conn), Helpers.body(params, "policy")) do
      conn |> put_status(:created) |> json(serialize(policy))
    end
  end

  operation(:update,
    summary: "Update a cancellation policy (creates a new version)",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Cancellation policy", "application/json", PolicyRequest},
    responses: [
      ok: {"Cancellation policy", "application/json", PolicyResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/policies/:id"
  def update(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :update, :cancellation_policy),
         {:ok, policy} <-
           Policies.update_policy(Helpers.actor(conn), id, Helpers.body(params, "policy")) do
      json(conn, serialize(policy))
    end
  end

  operation(:archive,
    summary: "Archive a cancellation policy",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Cancellation policy", "application/json", PolicyResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/policies/:id/archive"
  def archive(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :archive, :cancellation_policy),
         {:ok, policy} <- Policies.archive_policy(Helpers.actor(conn), id) do
      json(conn, serialize(policy))
    end
  end

  operation(:set_default,
    summary: "Make a cancellation policy the tenant default",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Cancellation policy", "application/json", PolicyResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/policies/:id/default"
  def set_default(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :set_default, :cancellation_policy),
         {:ok, policy} <- Policies.set_default(Helpers.actor(conn), id) do
      json(conn, serialize(policy))
    end
  end

  operation(:assign,
    summary: "Assign a policy to offerings",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Offerings", "application/json", AssignmentRequest},
    responses: [
      ok: {"Assignments", "application/json", AssignmentListResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/policies/:id/assign"
  def assign(conn, %{"id" => id} = params) do
    with :ok <- Helpers.authorize(conn, :assign, :offering_policy_assignment),
         {:ok, assignments} <-
           Policies.assign_offerings(Helpers.actor(conn), id, Helpers.offering_ids(params)) do
      json(conn, %{data: Enum.map(assignments, &PoliciesJSON.assignment/1)})
    end
  end

  operation(:unassign,
    summary: "Remove the policy assignment for an offering",
    parameters: [offering_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Removed", "application/json", AssignmentRemovalResponse}
    ]
  )

  @doc "DELETE /api/staff/policies/assignments/:offering_id"
  def unassign(conn, %{"offering_id" => offering_id}) do
    with :ok <- Helpers.authorize(conn, :unassign, :offering_policy_assignment),
         {:ok, removed} <- Policies.unassign_offering(Helpers.actor(conn), offering_id) do
      json(conn, %{offering_id: offering_id, removed: removed})
    end
  end

  operation(:simulate,
    summary: "Simulate a cancellation/rebooking outcome",
    request_body: {"Simulation", "application/json", SimulationRequest},
    responses: [
      ok: {"Outcome", "application/json", SimulationResponse}
    ]
  )

  @doc "POST /api/staff/policies/simulate"
  def simulate(conn, params) do
    with :ok <- Helpers.authorize(conn, :simulate, :cancellation_policy) do
      result = Policies.simulate(Map.get(params, "policy_id"), params)
      json(conn, PoliciesJSON.simulation(result))
    end
  end

  defp serialize(policy) do
    PoliciesJSON.policy(policy, Policies.assigned_offering_ids(policy.id))
  end
end
