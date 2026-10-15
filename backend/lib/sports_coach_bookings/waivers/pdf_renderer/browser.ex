defmodule SportsCoachBookings.Waivers.PdfRenderer.Browser do
  @moduledoc """
  Branded Unicode waiver rendering through a supervised, script-disabled
  Chromium process. Production uses this renderer; the pure-Elixir Document
  renderer remains the lightweight dev/test fallback.
  """

  @behaviour SportsCoachBookings.Waivers.PdfRenderer

  alias SportsCoachBookings.Waivers.PdfData
  alias SportsCoachBookings.Waivers.PdfHtml
  alias SportsCoachBookings.Waivers.PdfRenderer.Document
  alias SportsCoachBookings.Waivers.PdfStore

  @impl true
  def render(signature) do
    with {:ok, data} <- PdfData.load(signature),
         {:ok, encoded} <-
           ChromicPDF.print_to_pdf({:html, PdfHtml.build(data)},
             print_to_pdf: %{preferCSSPageSize: true, printBackground: true},
             telemetry_metadata: %{document: :waiver}
           ),
         {:ok, pdf} <- Base.decode64(encoded),
         key = Document.key(signature),
         :ok <- PdfStore.put(key, pdf) do
      {:ok, key}
    end
  end
end
