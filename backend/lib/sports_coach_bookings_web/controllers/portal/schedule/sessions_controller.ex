defmodule SportsCoachBookingsWeb.Portal.Schedule.SessionsController do
  @moduledoc "Public portal calendar of upcoming, bookable sessions."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookingsWeb.SchedulingJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Scheduling, as: S

  tags(["portal"])

  operation(:index,
    summary: "List upcoming bookable sessions",
    parameters: [
      from: [in: :query, type: :string, required: false],
      to: [in: :query, type: :string, required: false],
      offering_id: [in: :query, type: :string, required: false],
      format: [in: :query, type: :string, required: false],
      venue_id: [in: :query, type: :string, required: false],
      coach_id: [in: :query, type: :string, required: false],
      player_id: [in: :query, type: :string, required: false]
    ],
    responses: [
      ok: {"Calendar", "application/json", S.calendar_list_response()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/sessions"
  def index(conn, params) do
    with :ok <- Scheduling.Policy.authorize(customer_actor(conn), :list_public, :calendar),
         {:ok, opts} <- player_opts(conn, params),
         entries when is_list(entries) <- Scheduling.portal_sessions(params, opts) do
      json(conn, SchedulingJSON.collection(Enum.map(entries, &SchedulingJSON.calendar_entry/1)))
    end
  end

  operation(:show,
    summary: "Get a public session",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Session", "application/json", S.calendar_entry()},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/sessions/:id"
  def show(conn, %{"id" => id} = params) do
    with :ok <- Scheduling.Policy.authorize(customer_actor(conn), :list_public, :calendar),
         {:ok, opts} <- player_opts(conn, params),
         {:ok, entry} <- Scheduling.portal_session(id, opts) do
      json(conn, SchedulingJSON.calendar_entry(entry))
    end
  end

  defp customer_actor(conn), do: conn.assigns[:current_customer_actor]

  defp player_opts(conn, params) do
    case params["player_id"] do
      nil ->
        {:ok, []}

      player_id ->
        with {:ok, player} <- Players.fetch_player(player_id),
             :ok <- Players.Policy.authorize(customer_actor(conn), :get, player) do
          {:ok, [player: player]}
        end
    end
  end
end
