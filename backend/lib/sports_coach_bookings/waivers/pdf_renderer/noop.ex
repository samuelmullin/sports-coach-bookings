defmodule SportsCoachBookings.Waivers.PdfRenderer.Noop do
  @moduledoc """
  Default `SportsCoachBookings.Waivers.PdfRenderer` used in dev and test.

  It does not render or upload anything; it returns a deterministic object key
  derived from the signature id so the rest of the pipeline (Oban job, `pdf_key`
  column, download endpoint) is exercised end to end.
  """

  @behaviour SportsCoachBookings.Waivers.PdfRenderer

  @impl true
  def render(%{id: id}), do: {:ok, "waivers/#{id}.pdf"}
end
