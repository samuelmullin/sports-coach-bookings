defmodule SportsCoachBookingsWeb.Portal.Waivers.WaiversController do
  @moduledoc "Customer portal: required/signed waivers, signing, and PDF downloads."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Waivers
  alias SportsCoachBookingsWeb.PdfResponse
  alias SportsCoachBookingsWeb.Portal.Legal.Helpers, as: Documents
  alias SportsCoachBookingsWeb.Waivers.Helpers
  alias SportsCoachBookingsWeb.WaiversJSON

  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Legal.{EmailDocumentRequest, EmailDocumentResponse}

  alias SportsCoachBookingsWeb.Schemas.Waivers.{
    HouseholdWaiverStatusResponse,
    PlayerWaiverStatusResponse,
    SignWaiverRequest,
    WaiverSignatureResponse,
    WaiverVersionResponse
  }

  tags(["portal"])

  operation(:status,
    summary: "The household's per-player waiver status",
    responses: [
      ok: {"Waiver status", "application/json", HouseholdWaiverStatusResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/waivers/status"
  def status(conn, _params) do
    actor = conn.assigns[:current_customer_actor]

    with :ok <- Helpers.authorize(conn, :status, :waiver_status) do
      %{players: players} = Waivers.status_for_household(actor.household_id)
      json(conn, %{players: Enum.map(players, &WaiversJSON.player_status/1)})
    end
  end

  operation(:player_index,
    summary: "A player's required and signed waivers",
    parameters: [player_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Player waiver status", "application/json", PlayerWaiverStatusResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/players/:player_id/waivers"
  def player_index(conn, %{"player_id" => player_id}) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Helpers.authorize(conn, :list_player_waivers, player) do
      json(conn, WaiversJSON.player_status(Waivers.status_for_player(player.id)))
    end
  end

  operation(:show_version,
    summary: "Fetch a published waiver version body",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Waiver version", "application/json", WaiverVersionResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/waivers/versions/:id"
  def show_version(conn, %{"id" => id}) do
    with :ok <- Helpers.authorize(conn, :view_version, :waiver_version),
         {:ok, version} <- Waivers.fetch_version(id),
         :ok <- published_only(version) do
      json(conn, WaiversJSON.version(version))
    end
  end

  operation(:email_version,
    summary: "Email a copy of a published waiver version",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Recipient", "application/json", EmailDocumentRequest},
    responses: [
      accepted: {"Queued", "application/json", EmailDocumentResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid email", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/waivers/versions/:id/email"
  def email_version(conn, %{"id" => id} = params) do
    with {:ok, version} <- Waivers.fetch_version(id),
         :ok <- published_only(version),
         {:ok, email} <- Documents.resolve_email(conn, params),
         title = waiver_title(version),
         :ok <- Documents.send_copy(email, Documents.assigns(title, version.body_markdown)) do
      conn |> put_status(:accepted) |> json(%{status: "queued", email: email})
    end
  end

  operation(:sign,
    summary: "Sign a waiver version for a player",
    parameters: [
      player_id: [in: :path, type: :string, required: true],
      version_id: [in: :path, type: :string, required: true]
    ],
    request_body: {"Signature", "application/json", SignWaiverRequest},
    responses: [
      created: {"Waiver signature", "application/json", WaiverSignatureResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Stale or validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/players/:player_id/waivers/:version_id/sign"
  def sign(conn, %{"player_id" => player_id, "version_id" => version_id} = params) do
    with {:ok, player} <- Players.fetch_player(player_id),
         :ok <- Helpers.authorize(conn, :sign, player) do
      attrs =
        params
        |> Helpers.body("signature")
        |> Map.merge(%{"ip" => Helpers.ip(conn), "user_agent" => Helpers.user_agent(conn)})

      case Waivers.sign(Helpers.actor(conn), player.id, version_id, attrs) do
        {:ok, signature} ->
          conn |> put_status(:created) |> json(WaiversJSON.signature(signature))

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  operation(:pdf,
    summary: "Download one of your signatures' PDF snapshot",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Signed waiver PDF", "application/pdf", PdfResponse.schema()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/waivers/signatures/:id/pdf"
  def pdf(conn, %{"id" => id}) do
    with {:ok, signature} <- Waivers.fetch_signature(id),
         {:ok, player} <- Players.fetch_player(signature.player_id),
         :ok <- Helpers.authorize(conn, :download_pdf, player),
         {:ok, pdf} <- Waivers.pdf_binary(signature) do
      PdfResponse.send_pdf(conn, pdf, "waiver-#{signature.id}.pdf")
    end
  end

  defp published_only(%{status: status}) when status in [:published, :superseded], do: :ok
  defp published_only(_version), do: {:error, :not_found}

  defp waiver_title(version) do
    Waivers.get_template!(version.waiver_template_id).name
  rescue
    _ -> "Waiver"
  end
end
