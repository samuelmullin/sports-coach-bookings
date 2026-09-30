defmodule SportsCoachBookingsWeb.Staff.Feedback.FeedbackController do
  @moduledoc "Staff feedback API: create, list, read, edit, share, and skill tags."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Feedback
  alias SportsCoachBookings.Feedback.Policy
  alias SportsCoachBookingsWeb.FeedbackJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Feedback, as: S

  tags(["staff"])

  operation(:index,
    summary: "List feedback (owners/admins see all; coaches see their own)",
    parameters: [
      coach_id: [in: :query, type: :string, required: false],
      player_id: [in: :query, type: :string, required: false],
      session_id: [in: :query, type: :string, required: false],
      from: [in: :query, type: :string, required: false],
      to: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Feedback", "application/json", S.feedback_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/feedback"
  def index(conn, params) do
    actor = actor(conn)

    with :ok <- Policy.authorize(actor, :list, :feedback) do
      %{data: data, next_cursor: cursor} = Feedback.page_feedback(actor, filters(params), params)
      json(conn, FeedbackJSON.collection(Enum.map(data, &FeedbackJSON.feedback/1), cursor))
    end
  end

  operation(:create,
    summary: "Create feedback for a player in a session",
    request_body: {"Feedback", "application/json", S.create_request()},
    responses: [
      created: {"Feedback", "application/json", S.feedback()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/feedback"
  def create(conn, params) do
    with {:ok, feedback} <- Feedback.create_feedback(actor(conn), body(params, "feedback")) do
      conn |> put_status(:created) |> json(FeedbackJSON.feedback(feedback))
    end
  end

  operation(:skill_tags,
    summary: "List the tenant's feedback skill tags",
    responses: [
      ok: {"Skill tags", "application/json", S.skill_tag_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/feedback/skill_tags"
  def skill_tags(conn, _params) do
    with :ok <- Policy.authorize(actor(conn), :list_skill_tags, :skill_tag) do
      json(conn, %{data: Enum.map(Feedback.list_skill_tags(), &FeedbackJSON.skill_tag/1)})
    end
  end

  operation(:create_skill_tag,
    summary: "Create a feedback skill tag (owner/admin)",
    request_body: {"Skill tag", "application/json", S.create_skill_tag_request()},
    responses: [
      created: {"Skill tag", "application/json", S.skill_tag()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/feedback/skill_tags"
  def create_skill_tag(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :manage_skill_tags, :skill_tag),
         {:ok, tag} <- Feedback.create_skill_tag(actor(conn), body(params, "skill_tag")) do
      conn |> put_status(:created) |> json(FeedbackJSON.skill_tag(tag))
    end
  end

  operation(:show,
    summary: "Read a feedback row",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Feedback", "application/json", S.feedback()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/feedback/:id"
  def show(conn, %{"id" => id}) do
    with {:ok, feedback} <- Feedback.get_feedback(actor(conn), id) do
      json(conn, FeedbackJSON.feedback(feedback))
    end
  end

  operation(:update,
    summary: "Edit a feedback row (author, within the window)",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Feedback", "application/json", S.edit_request()},
    responses: [
      ok: {"Feedback", "application/json", S.feedback()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/feedback/:id"
  def update(conn, %{"id" => id} = params) do
    with {:ok, feedback} <-
           Feedback.edit_feedback(actor(conn), id, body(params, "feedback")) do
      json(conn, FeedbackJSON.feedback(feedback))
    end
  end

  operation(:share,
    summary: "Share feedback with the household (publishes feedback.submitted)",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Feedback", "application/json", S.feedback()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/feedback/:id/share"
  def share(conn, %{"id" => id}) do
    with {:ok, feedback} <- Feedback.share_feedback(actor(conn), id) do
      json(conn, FeedbackJSON.feedback(feedback))
    end
  end

  operation(:revisions,
    summary: "List a feedback row's edit revisions",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Revisions", "application/json", S.revisions_response()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/feedback/:id/revisions"
  def revisions(conn, %{"id" => id}) do
    with {:ok, _feedback} <- Feedback.get_feedback(actor(conn), id) do
      json(conn, %{data: Enum.map(Feedback.list_revisions(id), &FeedbackJSON.revision/1)})
    end
  end

  defp filters(params) do
    %{
      coach_id: params["coach_id"],
      player_id: params["player_id"],
      session_id: params["session_id"],
      from: parse_datetime(params["from"]),
      to: parse_datetime(params["to"])
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["id", "cursor", "limit", key])
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]
end
