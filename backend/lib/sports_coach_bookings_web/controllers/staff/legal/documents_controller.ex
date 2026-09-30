defmodule SportsCoachBookingsWeb.Staff.Legal.DocumentsController do
  @moduledoc """
  Staff API for legal documents: list versions and publish a new version. Only
  owners and admins may publish; coaches may read.
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Legal
  alias SportsCoachBookings.Legal.Policy
  alias SportsCoachBookingsWeb.LegalJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  alias SportsCoachBookingsWeb.Schemas.Legal.{
    LegalDocumentListResponse,
    LegalDocumentRequest,
    LegalDocumentResponse
  }

  tags(["staff"])

  operation(:index,
    summary: "List legal document versions",
    parameters: [
      kind: [in: :query, type: :string, required: false]
    ],
    responses: [
      ok: {"Legal documents", "application/json", LegalDocumentListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/legal_documents"
  def index(conn, params) do
    with :ok <- authorize(conn, :list) do
      documents = Legal.list_documents(Map.get(params, "kind"))
      json(conn, LegalJSON.collection(Enum.map(documents, &LegalJSON.summary/1)))
    end
  end

  operation(:create,
    summary: "Publish a new legal document version",
    request_body: {"Legal document", "application/json", LegalDocumentRequest},
    responses: [
      created: {"Legal document", "application/json", LegalDocumentResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/legal_documents"
  def create(conn, params) do
    with :ok <- authorize(conn, :publish),
         {:ok, document} <- Legal.publish_document(actor(conn), body(params)) do
      conn |> put_status(:created) |> json(LegalJSON.document(document))
    end
  end

  defp authorize(conn, action), do: Policy.authorize(actor(conn), action, :legal_document)

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp body(%{"document" => %{} = attrs}), do: attrs
  defp body(params), do: Map.drop(params, ["kind_filter", "cursor", "limit"])
end
