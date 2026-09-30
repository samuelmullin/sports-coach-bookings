defmodule Mix.Tasks.App.Openapi.Export do
  @shortdoc "Exports the OpenAPI spec to docs/openapi.json"
  @moduledoc """
  #{@shortdoc}

  Run from the `backend/` directory. The spec is written to the repo's
  `docs/openapi.json`, which `pnpm gen:api` consumes to regenerate the
  TypeScript client and MSW handlers.

      $ mix app.openapi.export
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile", [])

    spec = SportsCoachBookingsWeb.ApiSpec.spec()
    json = spec |> OpenApiSpex.OpenApi.to_map() |> Jason.encode!(pretty: true)

    output = Path.expand("../docs/openapi.json", File.cwd!())
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, json <> "\n")

    Mix.shell().info("Wrote #{output}")
  end
end
