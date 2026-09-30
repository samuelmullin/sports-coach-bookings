defmodule SportsCoachBookings.Waivers.PdfRenderer do
  @moduledoc """
  Renders a signed waiver to a PDF snapshot and stores it, returning the object
  storage key.

  No PDF renderer or object storage is configured in this repository yet, so the
  default implementation is `SportsCoachBookings.Waivers.PdfRenderer.Noop`,
  which returns a deterministic key without producing a file. A real renderer
  (for example ChromicPDF + S3) can be dropped in by setting
  `config :sports_coach_bookings, :waiver_pdf_renderer, MyRenderer`.

  See `docs/rfcs/20260928-waivers-pdf-stub.md`.
  """

  @doc "Renders `signature` and returns `{:ok, storage_key}`."
  @callback render(signature :: SportsCoachBookings.Waivers.WaiverSignature.t()) ::
              {:ok, binary()} | {:error, term()}

  @doc "The configured renderer module."
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :sports_coach_bookings,
      :waiver_pdf_renderer,
      SportsCoachBookings.Waivers.PdfRenderer.Noop
    )
  end
end
