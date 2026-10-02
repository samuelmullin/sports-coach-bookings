defmodule SportsCoachBookings.Waivers.PdfRenderer do
  @moduledoc """
  Renders a signed waiver to a PDF snapshot and stores it, returning the object
  storage key.

  The default is `SportsCoachBookings.Waivers.PdfRenderer.Document` (a real
  PDF written to `SportsCoachBookings.Waivers.PdfStore`). `Noop` remains for
  tests that only exercise the job pipeline; select another renderer with
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
      SportsCoachBookings.Waivers.PdfRenderer.Document
    )
  end
end
