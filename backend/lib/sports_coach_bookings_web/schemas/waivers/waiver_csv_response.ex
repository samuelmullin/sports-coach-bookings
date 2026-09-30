defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverCsvResponse do
  @moduledoc "CSV export of waiver signatures."

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WaiverCsvResponse",
    type: :string,
    format: :binary
  })
end
