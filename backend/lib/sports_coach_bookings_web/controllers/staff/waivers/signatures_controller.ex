defmodule SportsCoachBookingsWeb.Staff.Waivers.SignaturesController do
  @moduledoc "Staff listing, CSV export, and PDF download for waiver signatures."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Waivers
  alias SportsCoachBookingsWeb.Waivers.Helpers
  alias SportsCoachBookingsWeb.WaiversJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  alias SportsCoachBookingsWeb.Schemas.Waivers.{
    WaiverCsvResponse,
    WaiverPdfResponse,
    WaiverSignatureListResponse
  }

  tags(["staff"])

  operation(:index,
    summary: "List waiver signatures",
    parameters: [
      template_id: [in: :query, type: :string, required: false],
      version_id: [in: :query, type: :string, required: false],
      player_id: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Waiver signatures", "application/json", WaiverSignatureListResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/waivers/signatures"
  def index(conn, params) do
    with :ok <- Helpers.authorize(conn, :list_signatures, :waiver_signature) do
      filters = Helpers.signature_filters(params)
      %{data: data, next_cursor: cursor} = Waivers.page_signatures(filters, params)

      json(conn, WaiversJSON.collection(Enum.map(data, &WaiversJSON.signature/1), cursor))
    end
  end

  operation(:export,
    summary: "Export waiver signatures as CSV",
    parameters: [
      template_id: [in: :query, type: :string, required: false],
      version_id: [in: :query, type: :string, required: false],
      player_id: [in: :query, type: :string, required: false]
    ],
    responses: [
      ok: {"CSV", "text/csv", WaiverCsvResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/waivers/signatures/export"
  def export(conn, params) do
    with :ok <- Helpers.authorize(conn, :list_signatures, :waiver_signature) do
      csv = Waivers.export_signatures_csv(Helpers.signature_filters(params))

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="waiver_signatures.csv"))
      |> send_resp(200, csv)
    end
  end

  operation(:pdf,
    summary: "Download a signature's PDF snapshot",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"PDF metadata", "application/json", WaiverPdfResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/waivers/signatures/:id/pdf"
  def pdf(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :download_pdf, :waiver_signature),
         {:ok, signature} <- Waivers.fetch_signature(id) do
      json(conn, WaiversJSON.pdf(signature))
    end
  end
end
