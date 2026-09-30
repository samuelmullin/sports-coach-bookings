defmodule SportsCoachBookingsWeb.HealthController do
  @moduledoc """
  Liveness and readiness probes for the deploy platform.

  * `GET /health` — liveness. Always `200` while the app is accepting requests.
    Used by Fly's TCP/HTTP checks; deliberately does no database work.
  * `GET /health/ready` — readiness. Checks the database with a trivial query
    and returns `200`/`503`. Used to gate traffic during a deploy.

  These routes are **not** tenant-scoped and are excluded from `force_ssl`
  redirects (see `config/prod.exs`) so platform probes work over the private
  network. See `docs/rfcs/20260928-ops-health-endpoint.md`.
  """

  use SportsCoachBookingsWeb, :controller

  require Logger

  alias SportsCoachBookings.Repo

  @doc "GET /health"
  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end

  @doc "GET /health/ready"
  def ready(conn, _params) do
    case readiness() do
      :ok ->
        json(conn, %{status: "ok", checks: %{database: "ok"}})

      {:error, reason} ->
        # The probe is public: log the detail, return only a coarse status.
        Logger.error("readiness check failed", error: inspect(reason))

        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", checks: %{database: "error"}})
    end
  end

  defp readiness do
    case Repo.query("SELECT 1") do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
