defmodule SportsCoachBookingsWeb.Portal.Legal.DocumentsController do
  @moduledoc """
  Customer portal: read the tenant's active Terms of Service / Privacy Policy,
  and email a copy to an address. These endpoints are public (anonymous
  customers registering must be able to read the documents they are accepting).
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Legal
  alias SportsCoachBookingsWeb.LegalJSON
  alias SportsCoachBookingsWeb.Portal.Legal.Helpers
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  alias SportsCoachBookingsWeb.Schemas.Legal.{
    EmailDocumentRequest,
    EmailDocumentResponse,
    LegalDocumentListResponse,
    LegalDocumentResponse
  }

  tags(["portal"])

  operation(:index,
    summary: "List the tenant's active legal documents",
    responses: [
      ok: {"Active legal documents", "application/json", LegalDocumentListResponse}
    ]
  )

  @doc "GET /api/portal/documents"
  def index(conn, _params) do
    documents = Legal.list_active_documents()
    json(conn, LegalJSON.collection(Enum.map(documents, &LegalJSON.summary/1)))
  end

  operation(:show,
    summary: "Fetch the tenant's active legal document of a kind",
    parameters: [
      kind: [
        in: :path,
        type: :string,
        required: true,
        description: "Document kind, e.g. terms or privacy"
      ]
    ],
    responses: [
      ok: {"Legal document", "application/json", LegalDocumentResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/documents/:kind"
  def show(conn, %{"kind" => kind}) do
    with {:ok, document} <- Legal.active_document(kind) do
      json(conn, LegalJSON.document(document))
    end
  end

  operation(:email,
    summary: "Email a copy of the active legal document",
    parameters: [
      kind: [in: :path, type: :string, required: true]
    ],
    request_body: {"Recipient", "application/json", EmailDocumentRequest},
    responses: [
      accepted: {"Queued", "application/json", EmailDocumentResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid email", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/documents/:kind/email"
  def email(conn, %{"kind" => kind} = params) do
    with {:ok, document} <- Legal.active_document(kind),
         {:ok, email} <- Helpers.resolve_email(conn, params),
         :ok <- Helpers.send_copy(email, Legal.document_assigns(document)) do
      conn |> put_status(:accepted) |> json(%{status: "queued", email: email})
    end
  end
end
