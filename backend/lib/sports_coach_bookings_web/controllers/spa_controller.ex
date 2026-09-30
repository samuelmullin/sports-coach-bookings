defmodule SportsCoachBookingsWeb.SpaController do
  @moduledoc """
  Serves the built single-page apps with history fallback.

  In production the Phoenix app serves `frontend/apps/admin/dist` under `/admin`
  and `frontend/apps/portal/dist` under `/`. In local development these are
  served by the Vite dev servers instead (see `frontend/vite.config.ts`).

  Requests under `/api`, `/webhooks`, and `/dev` are never handled here.
  """

  use SportsCoachBookingsWeb, :controller

  @reserved ~w(api webhooks dev)

  @doc "GET /admin/*path"
  def admin(conn, params), do: serve(conn, :admin, params)

  @doc "GET /*path"
  def portal(conn, params) do
    if reserved?(params) do
      not_found(conn)
    else
      serve(conn, :portal, params)
    end
  end

  # sobelow_skip ["Traversal"]
  defp serve(conn, app, params) do
    root = Path.expand("frontend/apps/#{app}/dist", repo_root())
    requested = params["path"] |> List.wrap() |> Enum.join("/")
    candidate = Path.expand(requested, root)

    cond do
      not File.dir?(root) ->
        unavailable(conn, app)

      within_root?(candidate, root) and File.regular?(candidate) ->
        serve_file(conn, candidate)

      true ->
        index = Path.join(root, "index.html")

        if File.regular?(index) do
          serve_file(conn, index)
        else
          unavailable(conn, app)
        end
    end
  end

  # Plug.Conn.send_file/3 does not set a content type in this stack, and the
  # SecurityHeaders plug sends `x-content-type-options: nosniff`, so without an
  # explicit type the browser refuses to render HTML or execute JS modules.
  #
  # `path` is always one of the app's own dist files: it is resolved with
  # Path.expand/2 and confined to the dist root by within_root?/2 above, and the
  # content type is derived from that static asset's extension.
  # sobelow_skip ["Traversal.SendFile", "XSS.ContentType"]
  defp serve_file(conn, path) do
    conn
    |> put_resp_content_type(MIME.from_path(path))
    |> send_file(200, path)
  end

  defp reserved?(%{"path" => [first | _]}), do: first in @reserved
  defp reserved?(_), do: false

  # Boundary-aware containment: `/root` must not accept `/root-evil`. `Path.expand`
  # has already resolved any `..` segments against `root`.
  defp within_root?(candidate, root) do
    candidate == root or String.starts_with?(candidate, root <> "/")
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found", message: "Not found", details: %{}}})
  end

  defp unavailable(conn, app) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      error: %{
        code: "frontend_not_built",
        message: "The #{app} frontend has not been built. Run `pnpm build` in frontend/.",
        details: %{}
      }
    })
  end

  defp repo_root, do: Application.get_env(:sports_coach_bookings, :repo_root, File.cwd!())
end
